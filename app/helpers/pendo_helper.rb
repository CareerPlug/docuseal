# frozen_string_literal: true

module PendoHelper
  def insert_pendo?
    ENV['PENDO_API_KEY'].present? && !pendo_impersonating?
  end

  def pendo_initialize_payload
    return {} unless signed_in?

    payload = { visitor: pendo_visitor }
    payload[:account] = pendo_account if current_account
    payload
  end

  private

  def pendo_impersonating?
    respond_to?(:true_user) && true_user.present? && current_user.present? && true_user != current_user
  end

  # Keep visitor/account ids numeric so they match the parent-app Pendo initialize payload.
  def pendo_visitor
    {
      id: current_user.external_user_id || current_user.id,
      email: current_user.email.to_s
    }
  end

  def pendo_account
    {
      id: current_account.external_account_id || current_account.id,
      name: current_account.name.to_s
    }
  end
end
