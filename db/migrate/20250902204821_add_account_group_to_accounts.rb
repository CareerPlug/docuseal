class AddAccountGroupToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_reference :accounts, :account_group, foreign_key: true
  end
end
