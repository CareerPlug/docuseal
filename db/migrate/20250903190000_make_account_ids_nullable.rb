class MakeAccountIdsNullable < ActiveRecord::Migration[8.0]
  def change
    change_column_null :templates, :account_id, true
    change_column_null :users, :account_id, true
    change_column_null :template_folders, :account_id, true
  end
end