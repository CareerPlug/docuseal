# frozen_string_literal: true

class ScopeExternalUserIdUniquenessToAccount < ActiveRecord::Migration[8.0]
  def change
    remove_index :users, :external_user_id
    add_index :users, [:account_id, :external_user_id], unique: true
  end
end
