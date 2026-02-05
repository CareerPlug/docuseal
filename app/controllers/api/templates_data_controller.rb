module Api
  class TemplatesDataController < ApplicationController
    include PrefillFieldsHelper
    include PartnershipContext

    # Don't require API token - this uses session auth from web interface
    skip_before_action :authenticate_via_token!
    before_action :authenticate_user!
    load_and_authorize_resource :template
    before_action :set_no_cache_headers

    def show
      ActiveRecord::Associations::Preloader.new(
        records: [@template],
        associations: [schema_documents: [:blob, { preview_images_attachments: :blob }]]
      ).call

      # Process prefill fields for template editing if user is available
      available_prefill_fields = current_user ? extract_prefill_fields : []

      template_data = @template.as_json.merge(
        documents: @template.schema_documents.as_json(
          methods: %i[metadata signed_uuid],
          include: { preview_images: { methods: %i[url metadata filename] } }
        ),
        available_prefill_fields: available_prefill_fields,
        partnership_context: partnership_request_context
      )

      render json: template_data, status: :ok
    end

    private

    def set_no_cache_headers
      response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, private'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
    end
  end
end
