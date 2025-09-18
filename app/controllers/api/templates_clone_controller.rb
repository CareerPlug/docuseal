# frozen_string_literal: true

module Api
  class TemplatesCloneController < ApiBaseController
    load_and_authorize_resource :template

    def create
      # Handle cloning from account group templates to specific accounts
      return clone_from_account_group_to_account if params[:account_id].present? && @template.account_group_id.present?

      authorize!(:create, @template)

      cloned_template = clone_template_with_service(Templates::Clone, @template)
      finalize_and_render_response(cloned_template)
    end

    private

    def clone_from_account_group_to_account
      cloned_template = Templates::CloneToAccount.call(
        @template,
        external_account_id: params[:account_id],
        current_user: current_user,
        author: current_user,
        name: params[:name],
        external_id: params[:external_id].presence || params[:application_key],
        folder_name: params[:folder_name]
      )

      cloned_template.source = :api
      finalize_and_render_response(cloned_template)
    rescue ArgumentError => e
      if e.message.include?('Unauthorized')
        render json: { error: e.message }, status: :forbidden
      elsif e.message.include?('must be an account group template')
        render json: { error: e.message }, status: :unprocessable_entity
      else
        render json: { error: e.message }, status: :bad_request
      end
    rescue ActiveRecord::RecordNotFound => e
      render json: { error: e.message }, status: :not_found
    end

    def clone_template_with_service(service_class, template, **extra_args)
      ActiveRecord::Associations::Preloader.new(
        records: [template],
        associations: [schema_documents: :preview_images_attachments]
      ).call

      cloned_template = service_class.call(
        template,
        author: current_user,
        name: params[:name],
        external_id: params[:external_id].presence || params[:application_key],
        folder_name: params[:folder_name],
        **extra_args
      )

      cloned_template.source = :api
      cloned_template
    end

    def finalize_and_render_response(cloned_template)
      schema_documents = Templates::CloneAttachments.call(template: cloned_template,
                                                          original_template: @template,
                                                          documents: params[:documents])

      cloned_template.save!

      enqueue_webhooks(cloned_template)
      SearchEntries.enqueue_reindex(cloned_template)

      render json: Templates::SerializeForApi.call(cloned_template, schema_documents)
    end

    def enqueue_webhooks(template)
      WebhookUrls.for_account_id(template.account_id, 'template.created').each do |webhook_url|
        SendTemplateCreatedWebhookRequestJob.perform_async('template_id' => template.id,
                                                           'webhook_url_id' => webhook_url.id)
      end
    end
  end
end
