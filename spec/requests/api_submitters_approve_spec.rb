# frozen_string_literal: true

describe 'API Submitters Approve' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) do
    create(:submission, template:, account:, created_by_user: user, requires_approval: true)
  end
  let(:submitter) do
    create(
      :submitter,
      submission:,
      account:,
      completed_at: 1.hour.ago,
      uuid: template.submitters.first['uuid']
    )
  end

  describe 'POST /api/submitters/:slug/approve' do
    context 'when authenticated with a valid token' do
      it 'sets approved_at on the submission' do
        expect do
          post "/api/submitters/#{submitter.slug}/approve",
               headers: { 'x-auth-token': user.access_token.token }
        end.to change { submission.reload.approved_at }.from(nil)

        expect(response).to have_http_status(:ok)
      end

      it 'does not enqueue any webhooks' do
        create(:webhook_url, account:, events: ['submission.completed'])

        expect do
          post "/api/submitters/#{submitter.slug}/approve",
               headers: { 'x-auth-token': user.access_token.token }
        end.not_to change(SendSubmissionCompletedWebhookRequestJob.jobs, :size)
      end

      it 'is idempotent when already approved' do
        submission.update!(approved_at: 1.hour.ago)
        original_approved_at = submission.approved_at

        post "/api/submitters/#{submitter.slug}/approve",
             headers: { 'x-auth-token': user.access_token.token }

        expect(submission.reload.approved_at).to eq(original_approved_at)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when authenticated with a different account token' do
      let(:other_user) { create(:user, account: create(:account)) }

      it 'returns forbidden' do
        post "/api/submitters/#{submitter.slug}/approve",
             headers: { 'x-auth-token': other_user.access_token.token }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post "/api/submitters/#{submitter.slug}/approve"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
