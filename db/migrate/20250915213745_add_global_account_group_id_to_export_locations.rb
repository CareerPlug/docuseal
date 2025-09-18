class AddGlobalAccountGroupIdToExportLocations < ActiveRecord::Migration[8.0]
  def change
    add_column :export_locations, :global_account_group_id, :integer
  end
end
