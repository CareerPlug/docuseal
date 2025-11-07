# frozen_string_literal: true

class TokenRefreshService
  def initialize(params)
    @params = params
  end

  def refresh_token
    user = find_user
    return nil unless user

    user.access_token&.destroy
    user.association(:access_token).reset
    user.reload

    user.create_access_token!
    user.access_token.token
  end

  private

  def find_user
    external_user_id = @params.dig(:user, :external_id)&.to_i
    return nil unless external_user_id

    # Get account context if provided
    account = find_account_from_params

    # Find user scoped to account
    user = if account.present?
             User.find_by(account_id: account.id, external_user_id: external_user_id)
           else
             User.find_by(account_id: nil, external_user_id: external_user_id)
           end

    unless user
      Rails.logger.warn(
        'Token refresh requested for non-existent user: ' \
        "external_id #{external_user_id}, account_id #{account&.id}"
      )
    end

    user
  end

  def find_account_from_params
    return nil if @params[:account].blank?

    external_account_id = @params.dig(:account, :external_id)&.to_i
    return nil unless external_account_id

    Account.find_by(external_account_id: external_account_id)
  end
end
