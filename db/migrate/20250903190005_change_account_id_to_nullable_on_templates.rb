class ChangeAccountIdToNullableOnTemplates < ActiveRecord::Migration[8.0]
  def change
    change_column_null :templates, :account_id, true
  end
end
