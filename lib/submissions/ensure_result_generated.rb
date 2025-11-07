# frozen_string_literal: true

module Submissions
  module EnsureResultGenerated
    WAIT_FOR_RETRY = 2.seconds
    CHECK_EVENT_INTERVAL = 1.second
    CHECK_COMPLETE_TIMEOUT = 90.seconds

    WaitForCompleteTimeout = Class.new(StandardError)
    NotCompletedYet = Class.new(StandardError)

    module_function

    def call(submitter)
      return [] unless submitter

      raise NotCompletedYet unless submitter.completed_at?

      last_complete_event = ApplicationRecord.uncached do
        submitter.document_generation_events.complete.order(:created_at).last
      end

      # Only return existing docs if they were generated AFTER the current completion
      # This handles re-completion after change requests by comparing timestamps
      if last_complete_event && last_complete_event.created_at >= submitter.completed_at
        return latest_documents_for_event(submitter, last_complete_event)
      end

      events =
        ApplicationRecord.uncached do
          DocumentGenerationEvent.where(submitter:).order(:created_at).to_a
        end

      last_event = events.last

      # Check if last event is start/retry AND was created after current completion
      # This means generation is actually in progress for THIS completion
      is_generation_in_progress = last_event&.event_name&.in?(%w[start retry]) &&
                                   last_event.created_at >= submitter.completed_at

      if is_generation_in_progress
        wait_for_complete_or_fail(submitter)
      else
        submitter.document_generation_events.create!(event_name: events.present? ? :retry : :start)

        documents = GenerateResultAttachments.call(submitter)

        # Only create "complete" event if one doesn't exist for this completion
        # Check if there's a complete event created AFTER this completion
        unless submitter.document_generation_events.complete.where('created_at >= ?', submitter.completed_at).exists?
          submitter.document_generation_events.create!(event_name: :complete)
        end

        documents
      end
    rescue ActiveRecord::RecordNotUnique
      sleep WAIT_FOR_RETRY

      retry
    rescue StandardError => e
      Rollbar.error(e) if defined?(Rollbar)

      submitter.document_generation_events.create!(event_name: :fail)

      raise
    end

    def wait_for_complete_or_fail(submitter)
      total_wait_time = 0

      loop do
        sleep CHECK_EVENT_INTERVAL
        total_wait_time += CHECK_EVENT_INTERVAL

        last_event =
          ApplicationRecord.uncached do
            DocumentGenerationEvent.where(submitter:).order(:created_at).last
          end

        break submitter.documents.reload if last_event.event_name.in?(%w[complete fail])

        raise WaitForCompleteTimeout if total_wait_time > CHECK_COMPLETE_TIMEOUT
      end
    end

    def latest_documents_for_event(submitter, event)
      # Return documents created during or after the last complete event
      # This ensures we get the most recent generation, not old ones
      submitter.documents.where('active_storage_attachments.created_at >= ?', event.created_at)
    end
  end
end
