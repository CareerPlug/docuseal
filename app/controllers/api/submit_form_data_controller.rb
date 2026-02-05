module Api
  class SubmitFormDataController < ApplicationController
    skip_before_action :authenticate_via_token!
    skip_authorization_check

    before_action :load_submitter
    before_action :set_no_cache_headers

    def show
      # Return empty if form already completed or in invalid state
      if invalid_state?
        return render json: { values: {}, attachments: [], fields: [], submitter: {} }
      end

      render json: {
        values: @submitter.values,
        attachments: build_attachments_response,
        fields: Submissions.filtered_conditions_fields(@submitter),
        submitter: @submitter.as_json(only: %i[uuid slug name phone email])
      }, status: :ok
    end

    private

    def load_submitter
      @submitter = Submitter.find_by!(slug: params[:slug])
    end

    def invalid_state?
      @submitter.completed_at? ||
        @submitter.declined_at? ||
        @submitter.submission.template&.archived_at? ||
        @submitter.submission.archived_at? ||
        @submitter.submission.expired?
    end

    def build_attachments_response
      attachments = ActiveStorage::Attachment
                    .where(record: @submitter.submission.submitters, name: :attachments)
                    .preload(:blob)

      attachments.map do |att|
        att.as_json(only: %i[uuid created_at], methods: %i[url filename content_type])
      end
    end

    def set_no_cache_headers
      response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
    end
  end
end
