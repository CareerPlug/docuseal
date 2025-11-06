# frozen_string_literal: true

module Api
  class SignedDocumentUrlsController < ApiBaseController
    load_and_authorize_resource :submission

    def show
      last_submitter = @submission.last_completed_submitter

      if last_submitter.blank?
        return render json: { error: 'Submission not completed' },
                      status: :unprocessable_entity
      end

      # Ensure documents are generated
      Submissions::EnsureResultGenerated.call(last_submitter)

      render json: {
        submission_id: @submission.id,
        submitter_id: last_submitter.id,
        documents: SignedDocumentUrlBuilder.new(last_submitter).call
      }
    end
  end
end
