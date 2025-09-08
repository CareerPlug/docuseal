# frozen_string_literal: true

module Api
  class ExternalAuthController < Api::ApiBaseController
    skip_before_action :authenticate_via_token!
    skip_authorization_check

    def user_token
      if params[:account].present?
        account = Account.find_or_create_by_external_id(
          params[:account][:external_id]&.to_i,
          name: params[:account][:name],
          locale: params[:account][:locale] || 'en-US',
          timezone: params[:account][:timezone] || 'UTC'
        )

        user = User.find_or_create_by_external_id(
          account,
          params[:user][:external_id]&.to_i,
          email: params[:user][:email],
          first_name: params[:user][:first_name],
          last_name: params[:user][:last_name],
          role: 'admin'
        )
      elsif params[:account_group].present?
        account_group = AccountGroup.find_or_create_by_external_id(
          params[:account_group][:external_id]&.to_i,
          name: params[:account_group][:name]
        )

        user = User.find_or_create_by_external_group_id(
          account_group,
          params[:user][:external_id]&.to_i,
          email: params[:user][:email],
          first_name: params[:user][:first_name],
          last_name: params[:user][:last_name],
          role: 'admin'
        )
      end

      render json: { access_token: user.access_token.token }
    rescue StandardError => e
      Rails.logger.error("External auth error: #{e.message}")
      Rollbar.error(e) if defined?(Rollbar)
      render json: { error: 'Internal server error' }, status: :internal_server_error
    end
  end
end
