class AddAccountGroupToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :account_group, foreign_key: true
  end
end
