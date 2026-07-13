# frozen_string_literal: true

# Runtime guardrail that alerts when an ATS-linked account or partnership is
# missing the WebhookUrl that points at the CareerPlug ATS endpoint.
#
# Complements the boot-time env-var guard (config/initializers/careerplug_webhook_config.rb)
# by catching *drift* at runtime: an owner whose ATS WebhookUrl was deleted, never
# created (e.g. created while the env var was temporarily blank), or points at a
# stale URL. Designed to be invoked periodically (rake task / scheduled ECS task).
module WebhookHealthCheck
  module_function

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
