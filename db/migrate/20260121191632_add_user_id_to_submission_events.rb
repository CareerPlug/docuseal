# frozen_string_literal: true

class AddUserIdToSubmissionEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :submission_events, :user, null: true, foreign_key: true
  end
end
