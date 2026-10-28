# frozen_string_literal: true

require 'digest'

# Backfills and normalizes the ATS-pointed WebhookUrl for every Account and Partnership.
#
# The on-create provisioning callback (Account#create_careerplug_webhook,
# Partnership#create_careerplug_webhook) only fires for records created after
# CAREERPLUG_WEBHOOK_URL/SECRET were set. Pre-existing owners were never covered,
# and rows from the PopulateWebhookUrls migration carry a stale event set missing
# submission.completed. This one-time task closes both gaps.
#
# Idempotent: re-running with correct config produces zero changes.
# ALWAYS run with DRY_RUN=1 first and inspect the output before the live run
# (see lib/tasks/webhooks.rake).
class CareerplugWebhookBackfill
  # Outcome of a run. duplicate_warnings lists owners with more than one
  # ATS-pointed row (detected, never auto-deleted).
  Result = Struct.new(:created, :updated, :unchanged, :duplicate_warnings, keyword_init: true) do
    def self.empty
      new(created: 0, updated: 0, unchanged: 0, duplicate_warnings: [])
    end
  end

  def self.run(dry_run: false) = new(dry_run:).run

  def initialize(dry_run: false)
    @dry_run = dry_run
    @result = Result.empty
  end

  def run
    return @result unless configured?

    Account.find_each { |account| upsert(account, WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS) }
    Partnership.find_each { |partnership| upsert(partnership, WebhookUrl::PARTNERSHIP_EVENTS) }
    @result
  end

  private

  def upsert(owner, events)
    existing = matching_webhooks(owner)

    if existing.size > 1
      warn_duplicates(owner, existing)
      return
    end

    webhook = existing.first || owner.webhook_urls.new
    webhook.assign_attributes(url: target_url, events: events, secret: target_secret)

    if webhook.new_record? then persist(webhook, :created)
    elsif webhook.changed? then persist(webhook, :updated)
    else
      @result.unchanged += 1
    end
  end

  # ATS-linked owners are matched by the CareerPlug header plus the target URL
  # path instead of the sha1 of the current env URL, so a corrected
  # CAREERPLUG_WEBHOOK_URL repairs the drifted row in place instead of creating
  # a sibling. Requiring the same path keeps a customer row that merely repeats
  # the (user-settable) header name from being repointed when only the host
  # drifts. Every other owner keeps the sha1 lookup: a customer row must never
  # be repointed or have its secret replaced with CAREERPLUG_WEBHOOK_SECRET.
  def matching_webhooks(owner)
    return owner.webhook_urls.where(sha1: target_sha1).to_a unless ats_linked_owner?(owner) && target_path.present?

    owner.webhook_urls.to_a.select { |webhook| ats_row?(webhook) }
  end

  def ats_row?(webhook)
    webhook.careerplug_secret? && url_path(webhook.url) == target_path
  end

  def target_path
    @target_path ||= url_path(target_url)
  end

  def url_path(url)
    return if url.blank?

    URI(url).path.presence
  rescue URI::Error
    nil
  end

  def ats_linked_owner?(owner)
    owner.is_a?(Partnership) || owner.external_account_id.present?
  end

  def warn_duplicates(owner, existing)
    @result.duplicate_warnings << { owner_class: owner.class.name, owner_id: owner.id,
                                    webhook_ids: existing.map(&:id) }
    log "DUPLICATE (no delete): #{owner.class} id=#{owner.id} has #{existing.size} " \
        "ATS-pointed rows: #{existing.map(&:id).join(', ')}"
  end

  def persist(webhook, counter)
    label = owner_label(webhook)
    action = counter == :created ? 'Would create' : 'Would update'
    log "#{@dry_run ? '[DRY RUN] ' : ''}#{action} #{label}"
    @result[counter] += 1
    return if @dry_run

    webhook.save!
  end

  def owner_label(webhook)
    webhook.account_id ? "Account=#{webhook.account_id}" : "Partnership=#{webhook.partnership_id}"
  end

  def configured?
    return true if target_url.present? && ENV['CAREERPLUG_WEBHOOK_SECRET'].present?

    log 'CAREERPLUG_WEBHOOK_URL/SECRET not set — no-op'
    false
  end

  def target_url = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
  def target_sha1 = Digest::SHA1.hexdigest(target_url.to_s)
  def target_secret = { 'X-CareerPlug-Secret' => ENV.fetch('CAREERPLUG_WEBHOOK_SECRET') }

  def log(message)
    $stdout.puts(message)
    Rails.logger.info(message)
  end
end
