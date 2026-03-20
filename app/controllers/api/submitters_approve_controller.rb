# frozen_string_literal: true

module Api
  class SubmittersApproveController < ApiBaseController
    before_action :load_submitter

    def approve
      submission = @submitter.submission

      submission.update!(approved_at: Time.current) unless submission.approved_at?

      render json: Submitters::SerializeForApi.call(@submitter), status: :ok
    end

    private

    def load_submitter
      @submitter = Submitter.find_by!(slug: params[:slug])
      authorize! :read, @submitter
    end
  end
end
