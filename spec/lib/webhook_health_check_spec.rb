# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebhookHealthCheck do
  let(:ats_url) { 'https://www.careerplug.com/api/docuseal/events' }

  around do |example|
    previous = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
    ENV['CAREERPLUG_WEBHOOK_URL'] = ats_url
    example.run
  ensure
    ENV['CAREERPLUG_WEBHOOK_URL'] = previous
  end

  describe '.sha1_for' do
    it 'returns the SHA1 hexdigest matching WebhookUrl#set_sha1' do
      expect(described_class.sha1_for(ats_url)).to eq(Digest::SHA1.hexdigest(ats_url))
    end

    it 'returns nil for a blank url' do
      expect(described_class.sha1_for(nil)).to be_nil
      expect(described_class.sha1_for('')).to be_nil
    end
  end

  describe '.missing_ats_webhooks' do
    let(:expected_sha1) { Digest::SHA1.hexdigest(ats_url) }

    context 'with an ATS-linked account that has the expected webhook' do
      let!(:account) do
        create(:account, external_account_id: 101).tap do |a|
          create(:webhook_url, account: a, url: ats_url,
                               events: %w[form.completed],
                               secret: { 'X-CareerPlug-Secret' => 's' })
        end
      end

      it 'is not flagged' do
        expect(described_class.missing_ats_webhooks).not_to include(an_object_having_attributes(id: account.id))
      end
    end

    context 'with an ATS-linked account missing the expected webhook' do
      let!(:account) { create(:account, external_account_id: 102) }

      it 'is flagged' do
        expect(described_class.missing_ats_webhooks).to include(an_object_having_attributes(id: account.id))
      end
    end

    context 'with an account whose webhook points at a different url' do
      let!(:account) { create(:account, external_account_id: 103) }

      before do
        create(:webhook_url, account: account, url: 'https://example.com/other', events: %w[form.completed])
      end

      it 'is still flagged (sha1 mismatch)' do
        expect(described_class.missing_ats_webhooks).to include(an_object_having_attributes(id: account.id))
      end
    end

    it 'ignores accounts with no external_account_id (not ATS-linked)' do
      account = create(:account, external_account_id: nil)
      expect(described_class.missing_ats_webhooks).not_to include(an_object_having_attributes(id: account.id))
    end

    it 'ignores archived accounts' do
      account = create(:account, external_account_id: 104, archived_at: Time.current)
      expect(described_class.missing_ats_webhooks).not_to include(an_object_having_attributes(id: account.id))
    end

    context 'with partnerships' do
      let!(:with_webhook) do
        create(:partnership).tap do |p|
          create(:webhook_url, partnership: p, account: nil, url: ats_url,
                               events: %w[template.preferences_updated])
        end
      end
      let!(:without_webhook) { create(:partnership) }

      it 'flags partnerships missing the expected webhook but not those with it' do
        findings = described_class.missing_ats_webhooks
        expect(findings).to include(an_object_having_attributes(id: without_webhook.id))
        expect(findings).not_to include(an_object_having_attributes(id: with_webhook.id))
      end
    end

    context 'when CAREERPLUG_WEBHOOK_URL is blank' do
      around do |example|
        previous = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
        ENV['CAREERPLUG_WEBHOOK_URL'] = ''
        example.run
      ensure
        ENV['CAREERPLUG_WEBHOOK_URL'] = previous
      end

      it 'returns an empty list (boot guard owns the missing-env case)' do
        create(:account, external_account_id: 999)
        expect(described_class.missing_ats_webhooks).to eq([])
      end
    end
  end

  describe '.report!' do
    before do
      allow(Rails.logger).to receive(:error)
      allow(Airbrake).to receive(:notify)
    end

    context 'when findings exist' do
      let!(:account) { create(:account, external_account_id: 201) }

      it 'logs an error and notifies Airbrake' do
        described_class.report!

        expect(Rails.logger).to have_received(:error).with(/missing an ATS-pointed WebhookUrl/)
        expect(Airbrake).to have_received(:notify).with(/Account##{account.id}/)
      end

      it 'returns the findings' do
        expect(described_class.report!.map(&:id)).to include(account.id)
      end
    end

    context 'when there are no findings' do
      before { create(:account, external_account_id: 202).tap { |a| create(:webhook_url, account: a, url: ats_url) } }

      it 'does not log or notify' do
        described_class.report!

        expect(Rails.logger).not_to have_received(:error)
        expect(Airbrake).not_to have_received(:notify)
      end

      it 'returns an empty array' do
        expect(described_class.report!).to eq([])
      end
    end
  end

  describe '.probe_delivery' do
    let(:ats_secret) { 'delivery_probe_secret' }

    around do |example|
      previous = ENV.fetch('CAREERPLUG_WEBHOOK_SECRET', nil)
      ENV['CAREERPLUG_WEBHOOK_SECRET'] = ats_secret
      example.run
    ensure
      ENV['CAREERPLUG_WEBHOOK_SECRET'] = previous
    end

    def stub_probe_response(status)
      response = status.nil? ? nil : instance_double(Faraday::Response, status: status)
      allow(SendWebhookRequest).to receive(:call).and_return(response)
    end

    it 'returns :healthy for a 2xx response' do
      stub_probe_response(200)

      expect(described_class.probe_delivery).to eq(:healthy)
    end

    it 'returns :secret_rejected for 401' do
      stub_probe_response(401)

      expect(described_class.probe_delivery).to eq(:secret_rejected)
    end

    it 'returns :secret_rejected for 403' do
      stub_probe_response(403)

      expect(described_class.probe_delivery).to eq(:secret_rejected)
    end

    it 'returns :endpoint_not_found for 404' do
      stub_probe_response(404)

      expect(described_class.probe_delivery).to eq(:endpoint_not_found)
    end

    it 'returns :endpoint_error for a 5xx response' do
      stub_probe_response(500)

      expect(described_class.probe_delivery).to eq(:endpoint_error)
    end

    it 'returns :unexpected_status for any other non-2xx response' do
      stub_probe_response(422)

      expect(described_class.probe_delivery).to eq(:unexpected_status)
    end

    it 'returns :transport_error when SendWebhookRequest.call returns nil' do
      stub_probe_response(nil)

      expect(described_class.probe_delivery).to eq(:transport_error)
    end

    it 'passes a transient WebhookUrl built from ENV with the probe event and an empty payload' do
      allow(WebhookUrl).to receive(:new).and_call_original
      allow(SendWebhookRequest).to receive(:call)
        .and_return(instance_double(Faraday::Response, status: 200))

      described_class.probe_delivery

      expect(WebhookUrl).to have_received(:new)
        .with(url: ats_url, secret: { 'X-CareerPlug-Secret' => ats_secret })
      expect(SendWebhookRequest).to have_received(:call)
        .with(an_instance_of(WebhookUrl), event_type: 'health.check', data: {})
    end

    context 'when CAREERPLUG_WEBHOOK_URL is blank' do
      around do |example|
        previous = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
        ENV['CAREERPLUG_WEBHOOK_URL'] = ''
        example.run
      ensure
        ENV['CAREERPLUG_WEBHOOK_URL'] = previous
      end

      it 'returns :unconfigured without sending a request' do
        allow(SendWebhookRequest).to receive(:call)

        expect(described_class.probe_delivery).to eq(:unconfigured)

        expect(SendWebhookRequest).not_to have_received(:call)
      end
    end

    context 'when CAREERPLUG_WEBHOOK_SECRET is blank' do
      around do |example|
        previous = ENV.fetch('CAREERPLUG_WEBHOOK_SECRET', nil)
        ENV['CAREERPLUG_WEBHOOK_SECRET'] = ''
        example.run
      ensure
        ENV['CAREERPLUG_WEBHOOK_SECRET'] = previous
      end

      it 'returns :unconfigured without sending a request' do
        allow(SendWebhookRequest).to receive(:call)

        expect(described_class.probe_delivery).to eq(:unconfigured)

        expect(SendWebhookRequest).not_to have_received(:call)
      end
    end

    context 'when CAREERPLUG_WEBHOOK_URL is malformed' do
      around do |example|
        previous = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
        ENV['CAREERPLUG_WEBHOOK_URL'] = 'https://exa mple.com/api/docuseal/events'
        example.run
      ensure
        ENV['CAREERPLUG_WEBHOOK_URL'] = previous
      end

      it 'returns :invalid_url without raising' do
        expect(described_class.probe_delivery).to eq(:invalid_url)
      end
    end

    it 'posts the env secret header and the health.check payload to the env url' do
      stub_request(:post, ats_url).to_return(status: 200, body: '{}')

      expect(described_class.probe_delivery).to eq(:healthy)

      expect(
        a_request(:post, ats_url).with do |request|
          headers = request.headers.transform_keys(&:downcase)
          payload = JSON.parse(request.body)
          headers['x-careerplug-secret'] == ats_secret &&
            payload.slice('event_type', 'data') == { 'event_type' => 'health.check', 'data' => {} }
        end
      ).to have_been_made.once
    end
  end

  describe '.report_delivery!' do
    let(:ats_secret) { 'delivery_probe_secret' }
    let(:reported_messages) { [] }

    around do |example|
      previous = ENV.fetch('CAREERPLUG_WEBHOOK_SECRET', nil)
      ENV['CAREERPLUG_WEBHOOK_SECRET'] = ats_secret
      example.run
    ensure
      ENV['CAREERPLUG_WEBHOOK_SECRET'] = previous
    end

    before do
      allow(Rails.logger).to receive(:error) { |message| reported_messages << message }
      allow(Airbrake).to receive(:notify) { |message| reported_messages << message }
    end

    context 'when the probe reports a failing outcome' do
      before do
        allow(SendWebhookRequest).to receive(:call)
          .and_return(instance_double(Faraday::Response, status: 401))
      end

      it 'logs and notifies Airbrake with the outcome and expected url sha1 but not the url or secret' do
        described_class.report_delivery!

        expect(reported_messages.size).to eq(2)
        expect(reported_messages).to all(include(':secret_rejected'))
        expect(reported_messages).to all(include(Digest::SHA1.hexdigest(ats_url)))

        joined = reported_messages.join
        expect(joined).not_to include(ats_url)
        expect(joined).not_to include(ats_secret)
      end
    end

    context 'when the probe reports a transport failure' do
      before { allow(SendWebhookRequest).to receive(:call).and_return(nil) }

      it 'alerts and returns :transport_error' do
        expect(described_class.report_delivery!).to eq(:transport_error)

        expect(reported_messages.size).to eq(2)
        expect(reported_messages).to all(include(':transport_error'))
      end
    end

    context 'when the probe is healthy' do
      before do
        allow(SendWebhookRequest).to receive(:call)
          .and_return(instance_double(Faraday::Response, status: 200))
      end

      it 'does not alert and returns :healthy' do
        expect(described_class.report_delivery!).to eq(:healthy)

        expect(reported_messages).to be_empty
      end
    end

    context 'when the probe is unconfigured' do
      around do |example|
        previous = ENV.fetch('CAREERPLUG_WEBHOOK_URL', nil)
        ENV['CAREERPLUG_WEBHOOK_URL'] = ''
        example.run
      ensure
        ENV['CAREERPLUG_WEBHOOK_URL'] = previous
      end

      it 'does not alert and returns :unconfigured' do
        expect(described_class.report_delivery!).to eq(:unconfigured)

        expect(reported_messages).to be_empty
      end
    end
  end
end
