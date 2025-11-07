# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Submissions::EnsureResultGenerated do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) { create(:submission, template:, created_by_user: user) }
  let(:submitter) { create(:submitter, submission:, uuid: SecureRandom.uuid) }

  before do
    create(:encrypted_config, key: EncryptedConfig::ESIGN_CERTS_KEY,
                              value: GenerateCertificate.call.transform_values(&:to_pem))
  end

  describe '.call' do
    context 'when submitter is not completed' do
      before do
        submitter.update!(completed_at: nil)
      end

      it 'raises NotCompletedYet error' do
        expect do
          described_class.call(submitter)
        end.to raise_error(Submissions::EnsureResultGenerated::NotCompletedYet)
      end
    end

    context 'when submitter is nil' do
      it 'returns empty array' do
        expect(described_class.call(nil)).to eq([])
      end
    end

    context 'when documents exist and complete event is after completion' do
      let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('test'), filename: 'test.pdf') }

      before do
        submitter.update!(completed_at: 5.minutes.ago)
        submitter.documents.attach(blob)

        # Create complete event AFTER documents were generated
        submitter.document_generation_events.create!(event_name: :complete)
      end

      it 'returns existing documents' do
        result = described_class.call(submitter)
        expect(result.map(&:blob)).to include(blob)
      end

      it 'does not generate new documents' do
        allow(Submissions::GenerateResultAttachments).to receive(:call)
        described_class.call(submitter)
        expect(Submissions::GenerateResultAttachments).not_to have_received(:call)
      end
    end

    context 'when complete event is stale (created before current completion)' do
      let(:old_blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('old'), filename: 'old.pdf') }

      before do
        # Old completion cycle
        submitter.update!(completed_at: 10.minutes.ago)
        submitter.documents.attach(old_blob)
        submitter.document_generation_events.create!(event_name: :complete)

        # Update timestamps to be old
        ActiveStorage::Attachment.where(record: submitter, name: 'documents')
                                 .update_all(created_at: 10.minutes.ago)
        submitter.document_generation_events.update_all(created_at: 10.minutes.ago)

        # New completion (re-completion after change request)
        submitter.update!(completed_at: Time.current)
      end

      it 'generates new documents' do
        allow(Submissions::GenerateResultAttachments).to receive(:call).with(submitter).and_return([])
        expect do
          described_class.call(submitter)
        end.to change { submitter.document_generation_events.count }.by(2) # retry + complete
        expect(Submissions::GenerateResultAttachments).to have_received(:call).with(submitter)
      end

      it 'creates a retry event (not start, since events exist)' do
        allow(Submissions::GenerateResultAttachments).to receive(:call).and_return([])

        described_class.call(submitter)

        # Should have 1 retry event
        expect(submitter.document_generation_events.where(event_name: :retry).count).to eq(1)
      end

      it 'creates a new complete event after generation' do
        allow(Submissions::GenerateResultAttachments).to receive(:call).and_return([])

        described_class.call(submitter)

        # Should have 2 complete events now (old + new)
        expect(submitter.document_generation_events.where(event_name: :complete).count).to eq(2)
      end
    end

    context 'when generation is in progress (start/retry event after completion)' do
      before do
        submitter.update!(completed_at: Time.current)
        submitter.document_generation_events.create!(event_name: :start)
      end

      it 'waits for completion' do
        # Simulate another process completing the generation
        allow(described_class).to receive(:wait_for_complete_or_fail) do
          submitter.document_generation_events.create!(event_name: :complete)
          submitter.documents
        end

        described_class.call(submitter)
        expect(described_class).to have_received(:wait_for_complete_or_fail).with(submitter)
      end
    end

    context 'when stale start/retry event exists from previous completion' do
      let(:old_blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('old'), filename: 'old.pdf') }

      before do
        # Old completion with stale start event
        submitter.update!(completed_at: 10.minutes.ago)
        submitter.document_generation_events.create!(event_name: :start)

        # Update to make it old
        submitter.document_generation_events.update_all(created_at: 10.minutes.ago)

        # New completion
        submitter.update!(completed_at: Time.current)
      end

      it 'does not wait for stale event' do
        allow(described_class).to receive(:wait_for_complete_or_fail)
        allow(Submissions::GenerateResultAttachments).to receive(:call).and_return([])

        described_class.call(submitter)

        expect(described_class).not_to have_received(:wait_for_complete_or_fail)
        expect(Submissions::GenerateResultAttachments).to have_received(:call)
      end

      it 'creates retry event for current completion' do
        allow(Submissions::GenerateResultAttachments).to receive(:call).and_return([])

        expect do
          described_class.call(submitter)
        end.to change { submitter.document_generation_events.where(event_name: :retry).count }.by(1)
      end
    end

    context 'when no events exist yet' do
      before do
        submitter.update!(completed_at: Time.current)
      end

      it 'creates start event and generates documents' do
        allow(Submissions::GenerateResultAttachments).to receive(:call).with(submitter).and_return([])

        expect do
          described_class.call(submitter)
        end.to change { submitter.document_generation_events.where(event_name: :start).count }.by(1)

        expect(Submissions::GenerateResultAttachments).to have_received(:call).with(submitter)
      end
    end

    context 'when generation fails' do
      before do
        submitter.update!(completed_at: Time.current)
        allow(Submissions::GenerateResultAttachments).to receive(:call).and_raise(
          StandardError.new('Generation failed')
        )
      end

      it 'creates fail event' do
        expect do
          described_class.call(submitter)
        end.to raise_error(StandardError)

        expect(submitter.document_generation_events.where(event_name: :fail).count).to eq(1)
      end
    end
  end
end
