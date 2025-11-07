# frozen_string_literal: true

# == Schema Information
#
# Table name: document_generation_events
#
#  id           :bigint           not null, primary key
#  event_name   :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  submitter_id :integer          not null
#
# Indexes
#
#  idx_on_submitter_id_event_name_9f2a7a9341         (submitter_id,event_name) UNIQUE WHERE ((event_name)::text = 'start'::text)
#  index_document_generation_events_on_submitter_id  (submitter_id)
#
# Foreign Keys
#
#  fk_rails_...  (submitter_id => submitters.id)
#
class DocumentGenerationEvent < ApplicationRecord
  belongs_to :submitter

  enum :event_name, {
    complete: 'complete',
    fail: 'fail',
    start: 'start',
    retry: 'retry'
  }, scope: false
end
