# frozen_string_literal: true

# Shared logic for determining if webhook requests should be retried
# Used across all Send*WebhookRequestJob classes
module WebhookRetryLogic
  module_function

  MAX_ATTEMPTS = 10

  # Determines if a failed webhook request should be retried
  #
  # @param response [HTTP::Response, nil] The HTTP response from the webhook request
  # @param attempt [Integer] Current retry attempt number
  # @param record [Template, Submission, Submitter] The record triggering the webhook
  # @return [Boolean] true if the webhook should be retried
  def should_retry?(response:, attempt:, record:)
    return false unless response.nil? || response.status.to_i >= 400
    return false if attempt > MAX_ATTEMPTS
    return true unless Docuseal.multitenant?

    # ATS-linked accounts are provisioned without the plan AccountConfig that eligible_for_retries?
    # requires, and these webhooks are their only status path, so they retry regardless of plan
    # entitlement. This deployment does not set MULTITENANT, so the gate above is already bypassed in
    # production: this removes a latent trap rather than adding retry volume. Do not widen it into a
    # general retry loosening -- every other account keeps today's no-retry entitlement, and retries
    # stay bounded by MAX_ATTEMPTS with the existing backoff.
    #
    # respond_to? and & are both required: eligible_for_retries? only tolerates a missing account in
    # its Template branch, and a Template can legitimately have no account.
    return true if record.respond_to?(:account) && record.account&.external_account_id.present?

    eligible_for_retries?(record) || false
  end

  # Checks if a record is eligible for webhook retries in multitenant mode
  # @param record [Template, Submission, Submitter] The record to check
  # @return [Boolean] true if eligible for retries
  def eligible_for_retries?(record)
    case record
    when Template
      record.partnership_id.present? || record.account&.account_configs&.exists?(key: :plan)
    when Submission, Submitter
      record.account.account_configs.exists?(key: :plan)
    else
      false
    end
  end
end
