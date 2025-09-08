class ChangeAccountIdToNullableOnTemplateFolders < ActiveRecord::Migration[8.0]
  def change
    change_column_null :template_folders, :account_id, true
  end
end
