class AddAccountGroupToTemplateFolders < ActiveRecord::Migration[8.0]
  def change
    add_reference :template_folders, :account_group, foreign_key: true
  end
end
