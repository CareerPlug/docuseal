# frozen_string_literal: true

class AddRequiresApprovalToSubmissions < ActiveRecord::Migration[7.2]
  def change
    add_column :submissions, :requires_approval, :boolean, default: false, null: false
    add_column :submissions, :approved_at, :datetime
    add_index :submissions, :approved_at
  end
end
