# frozen_string_literal: true

# Simple response object for testing
FakeResponse = Struct.new(:status)

RSpec.describe WebhookRetryLogic do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:template, account: account, author: user) }

  describe '.should_retry?' do
    context 'with successful response' do
      it 'does not retry' do
        response = FakeResponse.new(200)
        result = described_class.should_retry?(response: response, attempt: 1, record: template)
        expect(result).to be false
      end
    end

    context 'with failed response' do
      it 'retries on 4xx errors within attempt limit' do
        response = FakeResponse.new(400)
        result = described_class.should_retry?(response: response, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'retries on 5xx errors within attempt limit' do
        response = FakeResponse.new(500)
        result = described_class.should_retry?(response: response, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'retries on nil response within attempt limit' do
        result = described_class.should_retry?(response: nil, attempt: 5, record: template)
        expect(result).to be true
      end

      it 'does not retry when max attempts exceeded' do
        response = FakeResponse.new(500)
        result = described_class.should_retry?(response: response, attempt: 11, record: template)
        expect(result).to be false
      end
    end

    context 'when multitenant', :multitenant do
      let(:failed_response) { FakeResponse.new(500) }

      it 'retries for an ATS-linked account without a plan config' do
        ats_account = create(:account, external_account_id: 12_345)
        ats_template = create(:template, account: ats_account, author: create(:user, account: ats_account))

        result = described_class.should_retry?(response: failed_response, attempt: 5, record: ats_template)

        expect(result).to be true
      end

      it 'does not retry for a non-ATS account without a plan config' do
        result = described_class.should_retry?(response: failed_response, attempt: 5, record: template)

        expect(result).to be false
      end

      it 'retries for an account with a plan config' do
        create(:account_config, account: account, key: 'plan', value: true)

        result = described_class.should_retry?(response: failed_response, attempt: 5, record: template)

        expect(result).to be true
      end

      it 'does not retry without raising for a template without an account' do
        result = described_class.should_retry?(response: failed_response, attempt: 5, record: Template.new)

        expect(result).to be false
      end
    end
  end
end
