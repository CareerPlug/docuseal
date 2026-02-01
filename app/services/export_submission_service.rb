# frozen_string_literal: true

class ExportSubmissionService < ExportService
  attr_reader :submission

  def initialize(submission)
    super()
    @submission = submission
  end

  def call
    export_location = ExportLocation.default_location

    if export_location&.submissions_endpoint.blank?
      record_error('Export failed: Submission export endpoint is not configured.')
      return false
    end

    payload = build_payload
    response = post_to_api(payload, export_location.submissions_endpoint, export_location.extra_params)

    if response&.success?
      true
    else
      record_error("Failed to export submission ##{submission.id} events.")
      false
    end
  rescue Faraday::Error => e
    Rails.logger.error("Failed to export submission Faraday: #{e.message}")
    Rollbar.error("Failed to export submission: #{e.message}") if defined?(Rollbar)
    record_error("Network error occurred during export: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error("Failed to export submission: #{e.message}")
    Rollbar.error(e) if defined?(Rollbar)
    record_error("An unexpected error occurred during export: #{e.message}")
    false
  end

  private

  def build_payload
    {
      external_submission_id: submission.id,
      template_name: submission.template&.name,
      status: submission_status,
      submitter_data: submission.submitters.map do |submitter|
        {
          external_submitter_id: submitter.slug,
          name: submitter.name,
          email: submitter.email,
          status: submitter.status,
          completed_at: submitter.completed_at,
          declined_at: submitter.declined_at
        }
      end,
      created_at: submission.created_at,
      updated_at: submission.updated_at,
      # Include form field values for each submitter
      values: build_values_array,
      # Include granular submission events for audit trail
      submission_events: build_submission_events_array
    }
  end

  def submission_status
    # The status is tracked for each submitter, so we need to check the status of all submitters
    statuses = submission.submitters.map(&:status)

    if statuses.include?('declined')
      'declined'
    elsif statuses.all?('completed')
      'completed'
    elsif statuses.include?('changes_requested')
      'changes_requested'
    elsif statuses.any?('opened')
      'in_progress'
    elsif statuses.any?('sent')
      'sent'
    else
      'pending'
    end
  end

  # Build array of form field values from all submitters
  # Returns array of {field: name, value: value} hashes
  def build_values_array
    submission.submitters.flat_map do |submitter|
      build_submitter_values(submitter)
    end
  end

  # Build values for a single submitter
  def build_submitter_values(submitter)
    fields = submission.template_fields.presence || submission.template&.fields || []
    attachments_index = submitter.attachments.index_by(&:uuid)

    fields.filter_map do |field|
      next if field['submitter_uuid'] != submitter.uuid
      next if field['type'] == 'heading'

      field_name = field['name'].presence || "#{field['type'].titleize} Field"
      next unless submitter.values.key?(field['uuid']) || submitter.completed_at?

      value = fetch_field_value(field, submitter.values[field['uuid']], attachments_index)

      { field: field_name, value: }
    end
  end

  # Build array of submission events for audit trail
  def build_submission_events_array
    submission.submission_events.order(:event_timestamp).map do |event|
      {
        id: event.id,
        event_type: event.event_type,
        event_timestamp: event.event_timestamp.iso8601,
        data: event.data
      }
    end
  end

  # Fetch the value for a field, handling special types
  def fetch_field_value(field, value, attachments_index)
    if field['type'].in?(%w[image signature initials stamp payment])
      rails_storage_proxy_url(attachments_index[value])
    elsif field['type'] == 'file'
      Array.wrap(value).compact_blank.filter_map { |e| rails_storage_proxy_url(attachments_index[e]) }
    else
      value
    end
  end

  def rails_storage_proxy_url(attachment)
    return if attachment.blank?

    ActiveStorage::Blob.proxy_url(attachment.blob)
  end
end
