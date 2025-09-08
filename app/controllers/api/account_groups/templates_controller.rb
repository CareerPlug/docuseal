# frozen_string_literal: true

module Api
  module AccountGroups
    class TemplatesController < ApiBaseController
      def create
        account_group = AccountGroup.find_by!(external_account_group_id: params[:account_group_id])
        
        template = Template.new(template_params)
        template.account_group = account_group
        template.author = current_user
        
        if template.save
          render json: { 
            id: template.id,
            uuid: template.uuid,
            name: template.name,
            account_group_id: account_group.external_account_group_id
          }
        else
          render json: { errors: template.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def template_params
        params.require(:template).permit(:name, :external_id)
      end
    end
  end
end