# frozen_string_literal: true

module Api
  class SubmittersRequestChangesController < ApiBaseController
    before_action :load_submitter

    def request_changes
      unless @submitter.completed_at?
        return render json: { error: 'Submitter has not completed the form' }, status: :unprocessable_entity
      end

      unless @submitter.changes_requested_at?
        ApplicationRecord.transaction do
          @submitter.update!(changes_requested_at: Time.current, completed_at: nil)

          SubmissionEvents.create_with_tracking_data(
            @submitter,
            'request_changes',
            request,
            { reason: params[:reason], requested_by: current_user.id },
            current_user
          )
        end
      end

      render json: Submitters::SerializeForApi.call(@submitter), status: :ok
    end

    private

    def load_submitter
      @submitter = Submitter.find_by!(slug: params[:slug])
      authorize! :read, @submitter
    end
  end
end
