# frozen_string_literal: true

class TemplatesFormPreviewController < ApplicationController
  include IframeAuthentication
  include PartnershipContext

  layout 'form'

  skip_before_action :authenticate_via_token!
  before_action :authenticate_from_referer
  load_and_authorize_resource :template

  def show
    save_params
    @submitter = Submitter.new(uuid: params[:uuid] || @template.submitters.first['uuid'],
                               account: current_account,
                               submission: @template.submissions.new(template_submitters: @template.submitters,
                                                                     account: current_account))

    @submitter.submission.submitters = @template.submitters.map { |item| Submitter.new(uuid: item['uuid']) }

    Submissions.preload_with_pages(@submitter.submission)

    @attachments_index = ActiveStorage::Attachment.where(record: @submitter.submission.submitters, name: :attachments)
                                                  .preload(:blob).index_by(&:uuid)
  
    @form_configs = Submitters::FormConfigs.call(@submitter)
  end

  private

  def save_params
    permitted = preview_params
    @auth_token ||= permitted[:auth_token] || session[:auth_token]
    @task_preview_mode ||= permitted[:task_preview_mode]
    @accessible_partnership_ids ||= permitted[:accessible_partnership_ids]
    @external_account_id ||= permitted[:external_account_id]
  end

  def preview_params
    params.permit(
      :uuid,
      :auth_token,
      :external_account_id,
      :task_preview_mode,
      accessible_partnership_ids: []
    )
  end
end
