# frozen_string_literal: true

require 'addressable/uri'

# Runtime guardrail that alerts when an ATS-linked account or partnership is
# missing the WebhookUrl that points at the CareerPlug ATS endpoint.
#
# Complements the boot-time env-var guard (config/initializers/careerplug_webhook_config.rb)
# by catching *drift* at runtime: an owner whose ATS WebhookUrl was deleted, never
# created (e.g. created while the env var was temporarily blank), or points at a
# stale URL. Designed to be invoked periodically (rake task / scheduled ECS task).
module WebhookHealthCheck
  module_function

  # Event type and header used by the delivery probe. ATS answers an unknown
  # event_type with a warning and a 200 when the secret is valid, so the probe
  # proves endpoint and secret without touching any ATS state, at the cost of
  # one ignored warning per probe run.
  PROBE_EVENT_TYPE = 'health.check'
  PROBE_SECRET_HEADER = 'X-CareerPlug-Secret'

  # Outcomes that are not alerted: :healthy is the expected state and
  # :unconfigured is already owned by the boot guard.
  NON_ALERTING_OUTCOMES = %i[healthy unconfigured].freeze

  # Returns ATS-linked owners (Accounts + Partnerships) that have no WebhookUrl
  # pointing at the configured CAREERPLUG_WEBHOOK_URL.
  #
  # @return [Array<Account, Partnership>] empty when env is blank (boot guard owns
  #   that case) or when every ATS-linked owner has the expected webhook.
  def missing_ats_webhooks
    target_sha1 = sha1_for(ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil))
    return [] if target_sha1.nil?

    accounts = Account.active
                      .where.not(external_account_id: nil)
                      .where.not(id: ats_webhook_owner_ids(target_sha1, :account_id))

    partnerships = Partnership.where.not(id: ats_webhook_owner_ids(target_sha1, :partnership_id))

    accounts.to_a + partnerships.to_a
  end

  # Detects missing ATS webhooks and notifies Airbrake when any are found.
  # Airbrake groups notices by message string, so repeated identical findings
  # (same count + same owners) are deduplicated into one notice. A new notice
  # fires only when the findings change (new missing webhooks appear).
  #
  # @return [Array<Account, Partnership>] the findings (empty when healthy)
  def report!
    findings = missing_ats_webhooks
    return findings if findings.empty?

    message = format(
      'DocuSeal integrity: %<count>d ATS-linked owner(s) missing an ATS-pointed ' \
      'WebhookUrl (expected url sha1=%<sha1>s): %<owners>s',
      count: findings.size,
      sha1: sha1_for(ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)),
      owners: findings.map { |o| "#{o.class.name}##{o.id}" }.first(20).join(', ')
    )
    Rails.logger.error(message)
    Airbrake.notify(message)
    findings
  end

  # Sends one empty PROBE_EVENT_TYPE event to the configured ATS endpoint and
  # classifies the delivery outcome, so a misrouted URL or a stale secret is
  # caught before (or while) real events are dropped.
  #
  # Targets ENV only: the WebhookUrl given to SendWebhookRequest is transient and
  # no stored row is read, scanned or used, because building the probe from a row
  # can probe a customer row or a row that drifted from the configured URL
  # (missing_ats_webhooks flags that drift; the backfill repairs it).
  #
  # Goes through SendWebhookRequest.call rather than .post so the real
  # multitenant HTTPS/localhost guards and the Faraday rescue apply. HttpsError
  # and LocalhostError are only raised when Docuseal.multitenant? is true and
  # URI::Error is already rescued inside call, so in this deployment the live
  # guard here is Addressable::URI::InvalidURIError (a malformed env URL must
  # return :invalid_url instead of crashing the scheduled task).
  #
  # @return [Symbol] one of :unconfigured, :invalid_url, :transport_error or a
  #   classify_delivery outcome; never raises
  def probe_delivery
    url = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
    secret = ENV.fetch('CAREERPLUG_WEBHOOK_SECRET', nil)
    return :unconfigured if url.blank? || secret.blank?

    webhook_url = WebhookUrl.new(url: url, secret: { PROBE_SECRET_HEADER => secret })
    response = SendWebhookRequest.call(webhook_url, event_type: PROBE_EVENT_TYPE, data: {})
    return :transport_error if response.nil?

    classify_delivery(response.status)
  rescue SendWebhookRequest::HttpsError, SendWebhookRequest::LocalhostError,
         URI::Error, Addressable::URI::InvalidURIError
    :invalid_url
  end

  # Maps an HTTP status to a probe outcome. 401/403 is the stale-secret signal
  # and 404 the wrong-endpoint signal — the two failure modes seen in production.
  def classify_delivery(status)
    case status.to_i
    when 200..299 then :healthy
    when 401, 403 then :secret_rejected
    when 404 then :endpoint_not_found
    when 500..599 then :endpoint_error
    else :unexpected_status
    end
  end

  # Probes ATS delivery and alerts on every failing outcome. Airbrake groups
  # notices by message string, so repeated probes of the same broken config
  # collapse into one notice; :healthy and :unconfigured stay silent (missing
  # config is the boot guard's responsibility). The message carries the outcome
  # and the expected URL sha1 only — never the URL, the secret or a response body.
  #
  # Reuses SendWebhookRequest.call, so a transport failure also produces call's
  # own transport-error notice (two distinct Airbrake groups) and every probe
  # records a DocuSeal/Webhook/health.check metric.
  #
  # @return [Symbol] the probe outcome
  def report_delivery!
    outcome = probe_delivery
    return outcome if NON_ALERTING_OUTCOMES.include?(outcome)

    message = format(
      'DocuSeal ATS webhook delivery probe failed: %<outcome>p (expected url sha1=%<sha1>s)',
      outcome: outcome,
      sha1: sha1_for(ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil))
    )
    Rails.logger.error(message)
    Airbrake.notify(message)
    outcome
  end

  # Cleartext SHA1 of a webhook URL, matching the dedup key set by WebhookUrl#set_sha1.
  # Returns nil for a blank URL so callers can short-circuit (missing env is the
  # boot guard's responsibility, not ours).
  def sha1_for(url)
    return nil if url.blank?

    Digest::SHA1.hexdigest(url)
  end

  # IDs of owners that already have a WebhookUrl with the target sha1, for the
  # given foreign key column. Used as a NOT IN subquery so we never load every
  # account/partnership into memory.
  def ats_webhook_owner_ids(target_sha1, owner_column)
    WebhookUrl.where(sha1: target_sha1)
              .where.not(owner_column => nil)
              .select(owner_column)
  end
end
