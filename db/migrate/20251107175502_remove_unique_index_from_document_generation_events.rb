# frozen_string_literal: true

class RemoveUniqueIndexFromDocumentGenerationEvents < ActiveRecord::Migration[8.0]
  def change
    # Remove the partial unique index that covers both 'start' and 'complete'
    remove_index :document_generation_events,
                 column: [:submitter_id, :event_name],
                 where: "event_name IN ('start', 'complete')"

    # Add unique constraint only for 'start' events (allows multiple 'complete' events)
    add_index :document_generation_events,
              [:submitter_id, :event_name],
              unique: true,
              where: "event_name = 'start'"
  end
end
