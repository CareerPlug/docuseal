# frozen_string_literal: true

require 'rails_helper'
require 'careerplug_webhook_backfill'

RSpec.describe CareerplugWebhookBackfill do
  # The on-create callback on Account/Partnership provisions a canonical webhook
  # whenever CAREERPLUG_WEBHOOK_URL/SECRET are present. To test the backfill in
  # isolation we disable the callback during owner creation (ENV absent), then
  # restore ENV for the run. Mirrors the pattern in webhook_url_spec.rb.
  let(:target_url) { 'http://localhost:3000/api/docuseal/events' }
  let(:target_secret) { 'development_webhook_secret' }
  let(:configured_env) do
    ENV.to_h.merge('CAREERPLUG_WEBHOOK_URL' => target_url, 'CAREERPLUG_WEBHOOK_SECRET' => target_secret)
  end
  let(:callback_disabled_env) { ENV.to_h.except('CAREERPLUG_WEBHOOK_URL', 'CAREERPLUG_WEBHOOK_SECRET') }

  def run(dry_run: false)
    described_class.run(dry_run: dry_run)
  end

  # Create owners without the on-create callback firing (it no-ops when env vars are absent),
  # then restore the configured ENV so the subsequent `run` sees the real target URL/secret.
  def create_owner(factory, **attrs)
    stub_const('ENV', callback_disabled_env)
    owner = create(factory, **attrs)
    stub_const('ENV', configured_env)
    owner
  end

  def build_stale_webhook(owner)
    owner_attrs = owner.is_a?(Account) ? { account: owner, partnership: nil } : { partnership: owner, account: nil }
    build(:webhook_url,
          **owner_attrs,
          url: target_url,
          events: %w[form.viewed form.started form.completed form.declined],
          secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)
  end

  describe '.run' do
    before { stub_const('ENV', configured_env) }

    context 'when an Account has no ATS-pointed webhook' do
      it 'creates one with the canonical account events and secret' do
        account = create_owner(:account)

        expect { run }.to change(WebhookUrl, :count).by(1)

        webhook = account.webhook_urls.last
        expect(webhook.url).to eq(target_url)
        expect(webhook.events).to eq(WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS)
        expect(webhook.secret).to eq('X-CareerPlug-Secret' => target_secret)
      end
    end

    context 'when an Account has a stale webhook (old default events)' do
      it 'updates events to include submission.completed without creating a second row' do
        account = create_owner(:account)
        webhook = build_stale_webhook(account)
        original_id = webhook.id

        result = run

        expect(WebhookUrl.where(account_id: account.id).count).to eq(1)
        expect(WebhookUrl.find(original_id).events).to include('submission.completed')
        expect(WebhookUrl.find(original_id).events).to eq(WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS)
        expect(result.updated).to eq(1)
        expect(result.created).to eq(0)
      end
    end

    context 'when an Account webhook is already canonical' do
      it 'is unchanged' do
        account = create_owner(:account)
        webhook = build(:webhook_url, account: account, url: target_url,
                                      events: WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS,
                                      secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)
        original_updated_at = webhook.updated_at

        result = run

        expect(WebhookUrl.where(account_id: account.id).count).to eq(1)
        expect(WebhookUrl.find(webhook.id).updated_at).to eq(original_updated_at)
        expect(result.unchanged).to eq(1)
        expect(result.created).to eq(0)
        expect(result.updated).to eq(0)
      end
    end

    context 'when a Partnership has no ATS-pointed webhook' do
      it 'creates one with only template.preferences_updated' do
        partnership = create_owner(:partnership)

        expect { run }.to change(WebhookUrl, :count).by(1)

        webhook = partnership.webhook_urls.last
        expect(webhook.events).to eq(WebhookUrl::PARTNERSHIP_EVENTS)
        expect(webhook.events).to eq(%w[template.preferences_updated])
      end
    end

    context 'when a Partnership webhook is already canonical' do
      it 'is unchanged' do
        partnership = create_owner(:partnership)
        webhook = build(:webhook_url, partnership: partnership, account: nil, url: target_url,
                                      events: WebhookUrl::PARTNERSHIP_EVENTS,
                                      secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)

        result = run

        expect(result.unchanged).to eq(1)
        expect(WebhookUrl.find(webhook.id).events).to eq(WebhookUrl::PARTNERSHIP_EVENTS)
      end
    end

    describe 'idempotency' do
      it 'a second run changes nothing' do
        create_owner(:account)

        run
        count_after_first_run = WebhookUrl.count
        updated_at_after_first_run = WebhookUrl.first.updated_at

        result = run

        expect(WebhookUrl.count).to eq(count_after_first_run)
        expect(WebhookUrl.first.updated_at).to eq(updated_at_after_first_run)
        expect(result.created).to eq(0)
        expect(result.updated).to eq(0)
        expect(result.unchanged).to eq(1)
      end
    end

    context 'when an owner has duplicate ATS-pointed rows' do
      it 'records a warning and mutates nothing' do
        account = create_owner(:account)
        build(:webhook_url, account: account, url: target_url,
                            events: WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS,
                            secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)
        build(:webhook_url, account: account, url: target_url,
                            events: WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS,
                            secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)

        expect { run }.not_to change(WebhookUrl, :count)
        expect(WebhookUrl.where(account_id: account.id).count).to eq(2)
      end

      it 'reports exactly one duplicate_warning with both webhook ids' do
        account = create_owner(:account)
        first = build(:webhook_url, account: account, url: target_url,
                                    events: WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS,
                                    secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)
        second = build(:webhook_url, account: account, url: target_url,
                                     events: WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS,
                                     secret: { 'X-CareerPlug-Secret' => target_secret }).tap(&:save!)

        result = run

        expect(result.duplicate_warnings.length).to eq(1)
        warning = result.duplicate_warnings.first
        expect(warning[:owner_class]).to eq('Account')
        expect(warning[:owner_id]).to eq(account.id)
        expect(warning[:webhook_ids]).to contain_exactly(first.id, second.id)
      end
    end

    context 'with DRY_RUN=1' do
      it 'writes nothing but reports the would-be action' do
        create_owner(:account)

        expect { run(dry_run: true) }.not_to change(WebhookUrl, :count)

        # Re-running for real creates it, proving the dry run did not.
        result = run
        expect(result.created).to eq(1)
      end
    end

    context 'when env vars are missing' do
      it 'is a no-op that touches no rows' do
        create_owner(:account)
        stub_const('ENV', callback_disabled_env) # disable env AFTER owner creation, BEFORE run

        expect { run }.not_to change(WebhookUrl, :count)

        result = run
        expect(result.created).to eq(0)
        expect(result.updated).to eq(0)
        expect(result.unchanged).to eq(0)
      end
    end
  end

  describe 'WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS' do
    it 'includes submission.completed (the root-cause event this ticket fixes)' do
      expect(WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS).to include('submission.completed')
    end

    it 'matches the events the on-create Account callback provisions' do
      # The Account callback references this constant directly; this guards
      # against the drift that originally caused the missing event.
      expect(WebhookUrl::CAREERPLUG_ACCOUNT_EVENTS).to eq(%w[
                                                            form.started
                                                            form.completed
                                                            submission.completed
                                                            form.changes_requested
                                                            template.preferences_updated
                                                          ])
    end
  end
end
