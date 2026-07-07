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
end
