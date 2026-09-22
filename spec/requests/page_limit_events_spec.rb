# frozen_string_literal: true

require 'rails_helper'

describe 'PageLimitEvents' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:valid_params) do
    { page_count: '130', surface: 'builder', file_size: '1048576' }
  end

  describe 'POST /page_limit_events' do
    context 'when signed in' do
      before { sign_in(user) }

      it 'returns 204 on valid params' do
        post '/page_limit_events', params: valid_params

        expect(response).to have_http_status(:no_content)
      end

      it 'logs a structured line stamped with the account id' do
        allow(Rails.logger).to receive(:info)

        post '/page_limit_events', params: valid_params

        expect(Rails.logger).to have_received(:info).with(
          a_string_including('page_limit_blocked', "\"account_id\":#{account.id}", '"bucket":"121-150"')
        )
      end

      it 'derives the bucket server-side and ignores a client-supplied bucket' do
        allow(Rails.logger).to receive(:info)

        post '/page_limit_events', params: valid_params.merge(page_count: '250', bucket: '121-150')

        expect(response).to have_http_status(:no_content)
        expect(Rails.logger).to have_received(:info).with(a_string_including('"bucket":"201+"'))
      end

      context 'with invalid params' do
        it 'returns 422 when the page count is under the limit' do
          post '/page_limit_events', params: valid_params.merge(page_count: '5')

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns 422 when an integer param is pathologically long' do
          post '/page_limit_events', params: valid_params.merge(page_count: "1#{'0' * 30}")

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    context 'when authenticated via token header' do
      it 'returns 204' do
        post '/page_limit_events', params: valid_params, headers: { 'X-Auth-Token' => user.access_token.token }

        expect(response).to have_http_status(:no_content)
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        post '/page_limit_events', params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated with an invalid token' do
      it 'returns 401' do
        post '/page_limit_events', params: valid_params, headers: { 'X-Auth-Token' => 'invalid' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
