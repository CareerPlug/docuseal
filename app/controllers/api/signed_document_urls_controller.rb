# frozen_string_literal: true

module Api
  class SignedDocumentUrlsController < ApiBaseController
    load_and_authorize_resource :submission

    rescue_from DocumentSecurityService::SigningError, with: :render_signing_error

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

    private

    # ATS maps 5xx to Docuseal::DocusealError and shows an "unable to retrieve"
    # toast; a signed-URL failure must never leak a broken S3 URL to the browser.
    def render_signing_error(exception)
      Airbrake.notify(exception)
      render json: { error: 'Unable to generate secure document URLs' }, status: :bad_gateway
    end
  end
end
