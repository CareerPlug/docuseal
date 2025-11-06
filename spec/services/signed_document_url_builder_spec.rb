# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SignedDocumentUrlBuilder do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submission) { create(:submission, :with_submitters, template:, account:, created_by_user: author) }
  let(:submitter) { submission.submitters.first }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('test pdf content'),
      filename: 'test-document.pdf',
      content_type: 'application/pdf'
    )
  end

  before do
    ActiveStorage::Current.url_options = { host: 'test.example.com' }
    submitter.update!(completed_at: Time.current)
    submitter.documents.attach(blob)
  end

  describe '#call' do
    subject(:builder) { described_class.new(submitter) }

    it 'returns an array of document hashes' do
      result = builder.call

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
    end

    it 'includes document metadata' do
      result = builder.call.first

      expect(result[:name]).to eq('test-document.pdf')
      expect(result[:url]).to be_present
      expect(result[:size_bytes]).to be_a(Integer)
      expect(result[:content_type]).to eq('application/pdf')
    end

    context 'with standard storage' do
      it 'generates ActiveStorage proxy URLs' do
        result = builder.call.first

        expect(result[:url]).to include('/file/')
      end

      it 'includes expiration time in the URL' do
        expected_expiration = 1.hour.from_now.to_i

        allow(ActiveStorage::Blob).to receive(:proxy_url).and_call_original
        builder.call

        expect(ActiveStorage::Blob).to have_received(:proxy_url)
          .with(blob, hash_including(expires_at: expected_expiration))
      end
    end

    context 'with secured storage (aws_s3_secured)' do
      subject(:builder) { described_class.new(submitter_two) }

      let(:submitter_two) { submission.submitters.second || create(:submitter, submission:, uuid: 'submitter-uuid-1') }
      let(:secured_blob) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('test pdf content'),
          filename: 'secured-document.pdf',
          content_type: 'application/pdf'
        )
      end

      before do
        submitter_two.update!(completed_at: Time.current)
        submitter_two.documents.attach(secured_blob)

        # Stub the service_name method to simulate secured storage
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(ActiveStorage::Blob).to receive(:service_name).and_return('aws_s3_secured')
        # rubocop:enable RSpec/AnyInstance
      end

      it 'uses DocumentSecurityService for signed URLs' do
        allow(DocumentSecurityService).to receive(:signed_url_for)
          .and_return('https://signed-url.example.com')

        result = builder.call.first

        expect(result[:url]).to eq('https://signed-url.example.com')
      end
    end

    context 'with multiple documents' do
      let(:blob2) do
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('second pdf content'),
          filename: 'second-document.pdf',
          content_type: 'application/pdf'
        )
      end

      before do
        submitter.documents.attach(blob2)
      end

      it 'returns all documents' do
        result = builder.call

        expect(result.size).to eq(2)
        expect(result.pluck(:name)).to contain_exactly('test-document.pdf', 'second-document.pdf')
      end
    end
  end
end
