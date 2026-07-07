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

      it 'records a failure metric without notifying Airbrake (non-2xx is handled by retry logic)' do
        described_class.call(webhook_url, event_type: 'form.completed', data: { foo: 1 })

        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/form.completed/failure', 1)
        expect(nr_agent).to have_received(:record_metric).with('DocuSeal/Webhook/total/failure', 1)
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
