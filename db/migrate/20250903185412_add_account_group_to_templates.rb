class AddAccountGroupToTemplates < ActiveRecord::Migration[8.0]
  def change
    add_reference :templates, :account_group, foreign_key: true
  end
end
