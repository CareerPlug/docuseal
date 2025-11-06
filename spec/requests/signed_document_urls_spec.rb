# frozen_string_literal: true

require 'rails_helper'

describe 'Signed Document URLs API' do
  let(:account) { create(:account, :with_testing_account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }

  describe 'GET /api/submissions/:submission_id/signed_document_url' do
    context 'with a completed submission' do
      let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
      let(:completed_submitter) { submission.submitters.first }
      let(:builder) { instance_double(SignedDocumentUrlBuilder) }
      let(:fake_docs) { [{ name: 'completed-document.pdf', url: 'http://example.com/doc', size_bytes: 123, content_type: 'application/pdf' }] }

      before do
        completed_submitter.update!(completed_at: Time.current)
        allow(SignedDocumentUrlBuilder).to receive(:new).with(completed_submitter).and_return(builder)
        allow(builder).to receive(:call).and_return(fake_docs)
      end

      it 'returns signed URLs for completed documents' do
        allow(Submissions::EnsureResultGenerated).to receive(:call)

        get "/api/submissions/#{submission.id}/signed_document_url",
            headers: { 'x-auth-token': author.access_token.token }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['submission_id']).to eq(submission.id)
        expect(response.parsed_body['submitter_id']).to eq(completed_submitter.id)
        expect(response.parsed_body['documents']).to be_an(Array)
        expect(response.parsed_body['documents'].first['name']).to eq('completed-document.pdf')
      end

      it 'calls EnsureResultGenerated to generate documents' do
        allow(Submissions::EnsureResultGenerated).to receive(:call)

        get "/api/submissions/#{submission.id}/signed_document_url",
            headers: { 'x-auth-token': author.access_token.token }

        expect(SignedDocumentUrlBuilder).to have_received(:new).with(completed_submitter)
        expect(builder).to have_received(:call)
      end
    end

    context 'with an incomplete submission' do
      let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }

      it 'returns an error when submission is not completed' do
        get "/api/submissions/#{submission.id}/signed_document_url",
            headers: { 'x-auth-token': author.access_token.token }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq({ 'error' => 'Submission not completed' })
      end

      it 'does not call EnsureResultGenerated for incomplete submissions' do
        allow(Submissions::EnsureResultGenerated).to receive(:call)

        get "/api/submissions/#{submission.id}/signed_document_url",
            headers: { 'x-auth-token': author.access_token.token }

        expect(Submissions::EnsureResultGenerated).not_to have_received(:call)
      end
    end

    context 'with multiple completed submitters' do
      let(:template) { create(:template, submitter_count: 2, account:, author:) }
      let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }
      let(:last_submitter) { submission.submitters.last }
      let(:builder) { instance_double(SignedDocumentUrlBuilder, call: [{ name: 'second-document.pdf', url: 'http://example.com/2', size_bytes: 1, content_type: 'application/pdf' }]) }

      before do
        submission.submitters.first.update!(completed_at: 1.hour.ago)
        last_submitter.update!(completed_at: Time.current)
        allow(Submissions::EnsureResultGenerated).to receive(:call)
        allow(SignedDocumentUrlBuilder).to receive(:new).with(last_submitter).and_return(builder)
      end

      it 'returns documents from the last completed submitter' do
        get "/api/submissions/#{submission.id}/signed_document_url",
            headers: { 'x-auth-token': author.access_token.token }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['submitter_id']).to eq(last_submitter.id)
        expect(response.parsed_body['documents'].first['name']).to eq('second-document.pdf')
      end
    end

    context 'with authorization' do
      let(:testing_account) { account.testing_accounts.first }
      let(:testing_author) { create(:user, account: testing_account) }
      let(:testing_template) { create(:template, account: testing_account, author: testing_author) }
      let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }

      before { submission.submitters.first.update!(completed_at: Time.current) }

      it 'returns error when using testing API token for production submission' do
        get "/api/submissions/#{submission.id}/signed_document_url",
            headers: { 'x-auth-token': testing_author.access_token.token }

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to include('testing API key')
      end

      it 'returns error when using production API token for testing submission' do
        testing_submission = create(
          :submission,
          :with_submitters,
          template: testing_template,
          created_by_user: testing_author
        )
        testing_submission.submitters.first.update!(completed_at: Time.current)

        get "/api/submissions/#{testing_submission.id}/signed_document_url",
            headers: { 'x-auth-token': author.access_token.token }

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to include('production API key')
      end

      it 'returns error when no auth token is provided' do
        get "/api/submissions/#{submission.id}/signed_document_url"

        expect(response).to have_http_status(:unauthorized)
        expect(response.parsed_body).to eq({ 'error' => 'Not authenticated' })
      end

      it 'raises RecordNotFound when submission does not exist' do
        expect do
          get '/api/submissions/99999/signed_document_url',
              headers: { 'x-auth-token': author.access_token.token }
        end.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'when EnsureResultGenerated fails' do
      let(:submission) { create(:submission, :with_submitters, template:, created_by_user: author) }

      before do
        submission.submitters.first.update!(completed_at: Time.current)
      end

      it 'propagates the error' do
        allow(Submissions::EnsureResultGenerated).to receive(:call).and_raise(StandardError, 'Generation failed')

        expect do
          get "/api/submissions/#{submission.id}/signed_document_url",
              headers: { 'x-auth-token': author.access_token.token }
        end.to raise_error(StandardError, 'Generation failed')
      end
    end
  end
end
