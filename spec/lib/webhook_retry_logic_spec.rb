# frozen_string_literal: true

RSpec.describe WebhookRetryLogic do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:template, account: account, author: user) }

  describe '.should_retry?' do
    context 'with successful response' do
      it 'does not retry' do
        response = instance_double(HTTP::Response, status: 200)
        result = described_class.should_retry?(response: response, attempt: 1, record: template)
        expect(result).to be false
      end
    end

    context 'with failed response' do
      it 'retries on 4xx errors within attempt limit' do
        response = instance_double(HTTP::Response, status: 400)
        result = described_class.should_retry?(response: response, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'retries on 5xx errors within attempt limit' do
        response = instance_double(HTTP::Response, status: 500)
        result = described_class.should_retry?(response: response, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'retries on nil response within attempt limit' do
        result = described_class.should_retry?(response: nil, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'does not retry when max attempts exceeded' do
        response = instance_double(HTTP::Response, status: 500)
        result = described_class.should_retry?(response: response, attempt: 11, record: template)
        expect(result).to be false
      end
    end
  end
end
