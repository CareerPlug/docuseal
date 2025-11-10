# frozen_string_literal: true

# == Schema Information
#
# Table name: submitters
#
#  id                   :bigint           not null, primary key
#  changes_requested_at :datetime
#  completed_at         :datetime
#  declined_at          :datetime
#  email                :string
#  ip                   :string
#  metadata             :text             not null
#  name                 :string
#  opened_at            :datetime
#  phone                :string
#  preferences          :text             not null
#  sent_at              :datetime
#  slug                 :string           not null
#  timezone             :string
#  ua                   :string
#  uuid                 :string           not null
#  values               :text             not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :integer          not null
#  external_id          :string
#  submission_id        :integer          not null
#
# Indexes
#
#  index_submitters_on_account_id_and_id            (account_id,id)
#  index_submitters_on_completed_at_and_account_id  (completed_at,account_id)
#  index_submitters_on_email                        (email)
#  index_submitters_on_external_id                  (external_id)
#  index_submitters_on_slug                         (slug) UNIQUE
#  index_submitters_on_submission_id                (submission_id)
#
# Foreign Keys
#
#  fk_rails_...  (submission_id => submissions.id)
#
require 'rails_helper'

RSpec.describe Submitter do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:template, account: account, author: user) }
  let(:submission) do
    create(:submission, :with_submitters, template: template, account: account, created_by_user: user)
  end
  let(:submitter) { submission.submitters.first }

  describe '#status' do
    context 'when submitter is awaiting' do
      it 'returns awaiting' do
        expect(submitter.status).to eq('awaiting')
      end
    end

    context 'when submitter is sent' do
      before { submitter.update!(sent_at: Time.current) }

      it 'returns sent' do
        expect(submitter.status).to eq('sent')
      end
    end

    context 'when submitter is opened' do
      before do
        submitter.update!(sent_at: Time.current, opened_at: Time.current)
      end

      it 'returns opened' do
        expect(submitter.status).to eq('opened')
      end
    end

    context 'when submitter is completed' do
      before do
        submitter.update!(
          sent_at: Time.current,
          opened_at: Time.current,
          completed_at: Time.current
        )
      end

      it 'returns completed' do
        expect(submitter.status).to eq('completed')
      end
    end

    context 'when submitter is declined' do
      before { submitter.update!(declined_at: Time.current) }

      it 'returns declined' do
        expect(submitter.status).to eq('declined')
      end
    end

    context 'when submitter is declined but also completed' do
      before do
        submitter.update!(
          completed_at: Time.current,
          declined_at: Time.current
        )
      end

      it 'returns declined (declined takes precedence)' do
        expect(submitter.status).to eq('declined')
      end
    end

    context 'when submitter has changes requested' do
      before { submitter.update!(changes_requested_at: Time.current) }

      it 'returns changes_requested' do
        expect(submitter.status).to eq('changes_requested')
      end
    end

    context 'when submitter has changes requested but is also completed' do
      before do
        submitter.update!(
          completed_at: Time.current,
          changes_requested_at: Time.current
        )
      end

      it 'returns changes_requested (changes_requested takes precedence over completed)' do
        expect(submitter.status).to eq('changes_requested')
      end
    end
  end

  describe '#export_submission_on_status_change' do
    let(:export_location) { create(:export_location, :with_submissions_endpoint) }
    let(:export_service) { instance_double(ExportSubmissionService) }

    before do
      allow(ExportLocation).to receive(:default_location).and_return(export_location)
      allow(ExportSubmissionService).to receive(:new).with(submission).and_return(export_service)
      allow(export_service).to receive(:call).and_return(true)
    end

    context 'when status-related field changes' do
      it 'calls ExportSubmissionService when completed_at changes' do
        submitter.update!(completed_at: Time.current)
        expect(ExportSubmissionService).to have_received(:new).with(submission)
        expect(export_service).to have_received(:call)
      end

      it 'calls ExportSubmissionService when declined_at changes' do
        submitter.update!(declined_at: Time.current)
        expect(ExportSubmissionService).to have_received(:new).with(submission)
        expect(export_service).to have_received(:call)
      end

      it 'calls ExportSubmissionService when opened_at changes' do
        submitter.update!(opened_at: Time.current)
        expect(ExportSubmissionService).to have_received(:new).with(submission)
        expect(export_service).to have_received(:call)
      end

      it 'calls ExportSubmissionService when sent_at changes' do
        submitter.update!(sent_at: Time.current)
        expect(ExportSubmissionService).to have_received(:new).with(submission)
        expect(export_service).to have_received(:call)
      end
    end

    context 'when non-status field changes' do
      it 'does not call ExportSubmissionService when email changes' do
        submitter.update!(email: 'new@example.com')
        expect(ExportSubmissionService).not_to have_received(:new)
        expect(export_service).not_to have_received(:call)
      end

      it 'does not call ExportSubmissionService when name changes' do
        submitter.update!(name: 'New Name')
        expect(ExportSubmissionService).not_to have_received(:new)
        expect(export_service).not_to have_received(:call)
      end
    end

    context 'when export service raises an error' do
      before do
        allow(export_service).to receive(:call).and_raise(StandardError.new('Export failed'))
        allow(Rails.logger).to receive(:error)
      end

      it 'logs the error and does not re-raise' do
        expect { submitter.update!(completed_at: Time.current) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(
          'Failed to export submission on status change: Export failed'
        )
      end
    end

    context 'when ExportLocation.default_location returns nil' do
      before do
        allow(ExportLocation).to receive(:default_location).and_return(nil)
        allow(export_service).to receive(:call).and_return(false)
      end

      it 'calls ExportSubmissionService but service handles nil export location' do
        submitter.update!(completed_at: Time.current)
        expect(ExportSubmissionService).to have_received(:new).with(submission)
        expect(export_service).to have_received(:call)
      end
    end

    context 'when export location has no submissions_endpoint' do
      before do
        allow(export_location).to receive(:submissions_endpoint).and_return(nil)
        allow(export_service).to receive(:call).and_return(false)
      end

      it 'calls ExportSubmissionService but service handles missing endpoint' do
        submitter.update!(completed_at: Time.current)
        expect(ExportSubmissionService).to have_received(:new).with(submission)
        expect(export_service).to have_received(:call)
      end
    end
  end

  describe '#current_documents' do
    let(:blob_one) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test1'), filename: 'test1.pdf') }
    let(:blob_two) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test2'), filename: 'test2.pdf') }
    let(:blob_three) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test3'), filename: 'test3.pdf') }

    context 'when there are no complete events' do
      before do
        submitter.documents.attach(blob_one)
        submitter.documents.attach(blob_two)
      end

      it 'returns all documents' do
        expect(submitter.current_documents.count).to eq(2)
        expect(submitter.current_documents.map(&:blob)).to contain_exactly(blob_one, blob_two)
      end
    end

    context 'when there is one completion with documents generated after completion' do
      before do
        # Complete first
        submitter.update!(completed_at: Time.current)

        # Attach documents after completion
        submitter.documents.attach(blob_one)
        submitter.documents.attach(blob_two)
        submitter.document_generation_events.create!(event_name: :complete)
      end

      it 'returns all documents since they were created after completion' do
        expect(submitter.current_documents.count).to eq(2)
        expect(submitter.current_documents.map(&:blob)).to contain_exactly(blob_one, blob_two)
      end
    end

    context 'when there are multiple completions (re-completion after change request)' do
      let(:old_attachment) do
        # First completion cycle - set old timestamp
        submitter.update!(completed_at: 10.minutes.ago)
        submitter.documents.attach(blob_one)
        submitter.document_generation_events.create!(event_name: :complete)

        # Update attachment timestamp to match old completion
        attachment_record = submitter.documents.find_by(blob_id: blob_one.id)
        ActiveStorage::Attachment.where(id: attachment_record.id).update_all(created_at: 10.minutes.ago)
        attachment_record
      end

      before do
        # Change request cycle - reset completed_at
        submitter.update!(changes_requested_at: 5.minutes.ago, completed_at: nil)

        # Second completion cycle with NEW completion time
        submitter.update!(completed_at: Time.current)
        submitter.documents.attach(blob_two)
        submitter.documents.attach(blob_three)
        submitter.document_generation_events.create!(event_name: :complete)
      end

      it 'returns only documents from the most recent completion' do
        docs = submitter.current_documents
        expect(docs.count).to eq(2)
        expect(docs.map(&:blob)).to contain_exactly(blob_two, blob_three)
      end

      it 'excludes documents from previous completion cycles' do
        docs = submitter.current_documents
        expect(docs.map(&:blob)).not_to include(blob_one)
      end
    end

    context 'when old documents exist before completion timestamp' do
      let(:old_attachment) do
        # Attach old document and manually set old timestamp
        submitter.documents.attach(blob_one)
        attachment_record = submitter.documents.find_by(blob_id: blob_one.id)
        ActiveStorage::Attachment.where(id: attachment_record.id).update_all(created_at: 10.minutes.ago)
        attachment_record
      end

      before do
        # Complete and attach new document
        submitter.update!(completed_at: Time.current)
        submitter.documents.attach(blob_two)
        submitter.document_generation_events.create!(event_name: :complete)
      end

      it 'only returns documents created after completion timestamp' do
        docs = submitter.current_documents
        expect(docs.count).to eq(1)
        expect(docs.first.blob).to eq(blob_two)
      end

      it 'excludes documents created before completion timestamp' do
        docs = submitter.current_documents
        expect(docs.map(&:blob)).not_to include(blob_one)
      end
    end
  end
end
