# frozen_string_literal: true

RSpec.describe ProcessSubmitterCompletionJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) { create(:submission, template:, created_by_user: user) }
  let(:submitter) { create(:submitter, submission:, uuid: SecureRandom.uuid, completed_at: Time.current) }

  before do
    create(:encrypted_config, key: EncryptedConfig::ESIGN_CERTS_KEY,
                              value: GenerateCertificate.call.transform_values(&:to_pem))
  end

  describe '#perform' do
    it 'creates a completed submitter' do
      expect do
        described_class.new.perform('submitter_id' => submitter.id)
      end.to change(CompletedSubmitter, :count).by(1)

      completed_submitter = CompletedSubmitter.last
      submitter.reload

      expect(completed_submitter.submitter_id).to eq(submitter.id)
      expect(completed_submitter.submission_id).to eq(submitter.submission_id)
      expect(completed_submitter.account_id).to eq(submitter.submission.account_id)
      expect(completed_submitter.template_id).to eq(submitter.submission.template_id)
      expect(completed_submitter.source).to eq(submitter.submission.source)
    end

    it 'creates a completed document' do
      expect do
        described_class.new.perform('submitter_id' => submitter.id)
      end.to change(CompletedDocument, :count).by(1)

      completed_document = CompletedDocument.last

      expect(completed_document.submitter_id).to eq(submitter.id)
      expect(completed_document.sha256).to be_present
      expect(completed_document.sha256).to eq(submitter.documents.first.metadata['sha256'])
    end

    it 'raises an error if the submitter is not found' do
      expect do
        described_class.new.perform('submitter_id' => 'invalid_id')
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    context 'when all submitters are completed' do
      let(:submitter2) { create(:submitter, submission:, uuid: SecureRandom.uuid, completed_at: Time.current) }

      before do
        # Mark all submitters as completed
        submission.submitters.update_all(completed_at: Time.current)
      end

      it 'generates audit trail for the submission' do
        allow(Submissions::GenerateAuditTrail).to receive(:call).with(submission)

        described_class.new.perform('submitter_id' => submitter.id)

        expect(Submissions::GenerateAuditTrail).to have_received(:call).with(submission)
      end

      context 'when audit trail already exists from previous completion' do
        let(:old_audit_trail_blob) do
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new('old audit trail'),
            filename: 'audit_trail.pdf'
          )
        end

        let(:new_audit_trail_blob) do
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new('new audit trail'),
            filename: 'audit_trail.pdf'
          )
        end

        before do
          # Attach old audit trail from 10 minutes ago
          submission.audit_trail.attach(old_audit_trail_blob)
          ActiveStorage::Attachment.where(
            record: submission,
            name: 'audit_trail'
          ).update_all(created_at: 10.minutes.ago)

          # Mock the audit trail generation to create new attachment
          allow(Submissions::GenerateAuditTrail).to receive(:call) do |sub|
            sub.audit_trail.attach(new_audit_trail_blob)
          end
        end

        it 'generates new audit trail' do
          described_class.new.perform('submitter_id' => submitter.id)

          expect(Submissions::GenerateAuditTrail).to have_received(:call).with(submission)
        end

        it 'purges old audit trail attachments' do
          described_class.new.perform('submitter_id' => submitter.id)

          # Should only have the new audit trail
          audit_trails = ActiveStorage::Attachment.where(
            record: submission,
            name: 'audit_trail'
          )
          expect(audit_trails.count).to eq(1)
          expect(audit_trails.first.blob).to eq(new_audit_trail_blob)
        end
      end

      context 'when audit trail was created before latest completion (re-completion scenario)' do
        let(:audit_trail_blob) do
          ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new('old audit trail'),
            filename: 'audit_trail.pdf'
          )
        end

        before do
          # Create old audit trail before the current completion
          submission.audit_trail.attach(audit_trail_blob)
          ActiveStorage::Attachment.where(
            record: submission,
            name: 'audit_trail'
          ).update_all(created_at: 1.hour.ago)

          # Current completion is more recent
          submission.submitters.update_all(completed_at: Time.current)
        end

        it 'regenerates audit trail because it is stale' do
          allow(Submissions::GenerateAuditTrail).to receive(:call).with(submission)

          described_class.new.perform('submitter_id' => submitter.id)

          expect(Submissions::GenerateAuditTrail).to have_received(:call).with(submission)
        end
      end

      context 'when no audit trail exists' do
        it 'generates new audit trail' do
          allow(Submissions::GenerateAuditTrail).to receive(:call).with(submission)

          described_class.new.perform('submitter_id' => submitter.id)

          expect(Submissions::GenerateAuditTrail).to have_received(:call).with(submission)
        end
      end

      context 'when checking audit trail created_at (integration test)' do
        it 'can access created_at on ActiveStorage::Attachment record' do
          # This test verifies that we're using ActiveStorage::Attachment.find_by
          # instead of submission.audit_trail (which is a proxy and doesn't have created_at)
          audit_trail_blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new('audit trail'),
            filename: 'audit_trail.pdf'
          )
          submission.audit_trail.attach(audit_trail_blob)

          attachment = ActiveStorage::Attachment.find_by(
            record: submission,
            name: 'audit_trail'
          )

          expect(attachment).to be_present
          expect(attachment.created_at).to be_a(Time)
          expect { attachment.created_at < Time.current }.not_to raise_error
        end
      end
    end

    context 'when not all submitters are completed' do
      let(:submitter2) { create(:submitter, submission:, uuid: SecureRandom.uuid, completed_at: nil) }

      before do
        submitter2 # Create the incomplete submitter
      end

      it 'does not generate audit trail' do
        allow(Submissions::GenerateAuditTrail).to receive(:call)

        described_class.new.perform('submitter_id' => submitter.id)

        expect(Submissions::GenerateAuditTrail).not_to have_received(:call)
      end
    end
  end
end
