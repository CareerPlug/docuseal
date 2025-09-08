# frozen_string_literal: true

module Api
  class AccountGroupsController < ApiBaseController
    load_and_authorize_resource :account_group, class: AccountGroup

    def create_or_update
      @account_group = AccountGroup.find_or_initialize_by(
        external_account_group_id: params[:external_account_group_id]
      )

      @account_group.update!(account_group_params)
      render json: @account_group
    end

    def update_account_membership
      account = Account.find_by!(external_account_id: params[:external_account_id])
      account_group = AccountGroup.find_by!(external_account_group_id: params[:external_account_group_id])

      account.update!(account_group: account_group)
      render json: { success: true }
    end

    private

    def account_group_params
      params.require(:account_group).permit(:name, :external_account_group_id)
    end
  end
end