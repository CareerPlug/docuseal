# frozen_string_literal: true

class ScopeEmailUniquenessToAccount < ActiveRecord::Migration[8.0]
  def change
    remove_index :users, :email
    add_index :users, [:account_id, :email], unique: true, name: 'index_users_on_account_id_and_email'
  end
end
