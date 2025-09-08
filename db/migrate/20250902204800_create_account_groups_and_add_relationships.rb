class CreateAccountGroupsAndAddRelationships < ActiveRecord::Migration[8.0]
  def change
    create_table :account_groups do |t|
      t.string :external_account_group_id, null: false
      t.string :name, null: false

      t.timestamps
    end
    add_index :account_groups, :external_account_group_id, unique: true

    add_reference :accounts, :account_group, foreign_key: true
    add_reference :templates, :account_group, foreign_key: true
    add_reference :users, :account_group, foreign_key: true
    add_reference :template_folders, :account_group, foreign_key: true
  end
end