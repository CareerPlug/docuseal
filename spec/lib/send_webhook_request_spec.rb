# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWebhookRequest do
  let(:account) { create(:account) }
  let(:webhook_url) { create(:webhook_url, account: account, url: 'https://example.com/hook') }
  # Plain double (not verified) because we stub the whole ::NewRelic::Agent constant,
  # which may not be loaded depending on env — verifying doubles would fail to resolve it.
  let(:nr_agent) { double('NewRelic::Agent') } # rubocop:disable RSpec/VerifiedDoubles

  before do
    # The production code calls ::NewRelic::Agent.record_metric. The gem may not be
    # loaded in the test env, so stub the whole constant and record_metric on it.
    stub_const('NewRelic::Agent', nr_agent)
    allow(nr_agent).to receive(:record_metric)
    allow(Airbrake).to receive(:notify)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
  end

  describe '.call' do
    context 'when the request succeeds (2xx)' do
      before { stub_request(:post, 'https://example.com/hook').to_return(status: 200, body: '{}') }

      it 'records a success metric and does not notify Airbrake' do
        described_class.call(webhook_url, event_type: 'form.completed', data: { foo: 1 })

        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/form.completed/success', 1)
        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/total/success', 1)
        expect(Airbrake).not_to have_received(:notify)
      end
    end

    context 'when the request returns a non-2xx status' do
      before { stub_request(:post, 'https://example.com/hook').to_return(status: 500) }

      it 'records a failure metric without notifying Airbrake for a non-ATS row' do
        described_class.call(webhook_url, event_type: 'form.completed', data: { foo: 1 })

        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/form.completed/failure', 1)
        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/total/failure', 1)
        expect(Airbrake).not_to have_received(:notify)
      end
    end

    context 'when a non-2xx status comes from an ATS-pointed webhook' do
      let(:account) { create(:account, external_account_id: 9_003) }
      let(:secret_value) { 'ats-secret-value' }
      let(:webhook_url) do
        create(:webhook_url, account: account, url: 'https://example.com/hook',
                             secret: { 'X-CareerPlug-Secret' => secret_value })
      end

      before { stub_request(:post, 'https://example.com/hook').to_return(status: 500) }

      it 'logs a warning and notifies Airbrake once without the url or secret' do
        notifications = []
        allow(Airbrake).to receive(:notify) { |message| notifications << message }

        described_class.call(webhook_url, event_type: 'submission.completed', data: { foo: 1 })

        expect(Rails.logger).to have_received(:warn)
          .with(/submission\.completed.*webhook_url_id=#{webhook_url.id}.*status 500/)
        expect(Airbrake).to have_received(:notify).once
        expect(notifications.size).to eq(1)
        expect(notifications.first).to include('submission.completed', "webhook_url_id=#{webhook_url.id}",
                                               'status 500')
        expect(notifications.first).not_to include(webhook_url.url)
        expect(notifications.first).not_to include(secret_value)
      end
    end

    context 'when a non-2xx status comes from an unsaved probe row' do
      let(:probe_url) { 'https://probe.example.com/api/docuseal/events' }
      let(:probe) do
        WebhookUrl.new(url: probe_url, secret: { 'X-CareerPlug-Secret' => 'ats-secret-value' })
      end

      before { stub_request(:post, probe_url).to_return(status: 401) }

      it 'does not log a delivery warning or notify Airbrake' do
        described_class.call(probe, event_type: 'health.check', data: {})

        expect(probe.id).to be_nil
        expect(Rails.logger).not_to have_received(:warn)
        expect(Airbrake).not_to have_received(:notify)
      end
    end

    context 'when the request raises a Faraday::Error (transport failure)' do
      before do
        stub_request(:post, 'https://example.com/hook').to_raise(Faraday::ConnectionFailed.new('boom'))
      end

      it 'records a failure metric, logs, notifies Airbrake, and returns nil (retry path intact)' do
        result = described_class.call(webhook_url, event_type: 'form.completed', data: { foo: 1 })

        expect(result).to be_nil
        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/form.completed/failure', 1)
        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/total/failure', 1)
        expect(Rails.logger).to have_received(:error).with(/Webhook transport error.*form\.completed.*boom/)
        expect(Airbrake).to have_received(:notify).with(/DocuSeal outbound webhook transport error \(form.completed\)/)
      end
    end
  end
end
