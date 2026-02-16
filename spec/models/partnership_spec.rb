# frozen_string_literal: true

# == Schema Information
#
# Table name: partnerships
#
#  id                      :bigint           not null, primary key
#  name                    :string           not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  external_partnership_id :integer          not null
#
# Indexes
#
#  index_partnerships_on_external_partnership_id  (external_partnership_id) UNIQUE
#
describe Partnership do
  describe 'validations' do
    it 'validates presence of external_partnership_id' do
      partnership = build(:partnership, external_partnership_id: nil)
      expect(partnership).not_to be_valid
      expect(partnership.errors[:external_partnership_id]).to include("can't be blank")
    end

    it 'validates uniqueness of external_partnership_id' do
      create(:partnership, external_partnership_id: 123)
      duplicate = build(:partnership, external_partnership_id: 123)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_partnership_id]).to include('has already been taken')
    end

    it 'validates presence of name' do
      partnership = build(:partnership, name: nil)
      expect(partnership).not_to be_valid
      expect(partnership.errors[:name]).to include("can't be blank")
    end
  end

  describe 'callbacks' do
    describe '#create_careerplug_webhook' do
      context 'with CareerPlug env vars set' do
        before do
          stub_const('ENV', ENV.to_hash.merge(
                              'CAREERPLUG_WEBHOOK_URL' => 'https://example.com/webhooks',
                              'CAREERPLUG_WEBHOOK_SECRET' => 'test-secret-123'
                            ))
        end

        it 'creates a webhook after partnership creation' do
          expect do
            create(:partnership)
          end.to change(WebhookUrl, :count).by(1)
        end

        it 'creates webhook with correct attributes' do
          partnership = create(:partnership)
          webhook = partnership.webhook_urls.last

          expect(webhook.url).to eq('https://example.com/webhooks')
          expect(webhook.events).to match_array(WebhookUrl::PARTNERSHIP_EVENTS)
          expect(webhook.secret).to eq({ 'X-CareerPlug-Secret' => 'test-secret-123' })
        end

        it 'does not create duplicate webhooks' do
          partnership = create(:partnership)
          initial_count = WebhookUrl.count

          # Call it again - should not create another webhook
          partnership.create_careerplug_webhook

          expect(WebhookUrl.count).to eq(initial_count)
        end
      end

      context 'without CareerPlug env vars' do
        before do
          stub_const('ENV', ENV.to_hash.except('CAREERPLUG_WEBHOOK_URL', 'CAREERPLUG_WEBHOOK_SECRET'))
        end

        it 'does not create a webhook' do
          expect do
            create(:partnership)
          end.not_to change(WebhookUrl, :count)
        end
      end

      context 'with only webhook URL set' do
        before do
          stub_const('ENV', ENV.to_hash.merge('CAREERPLUG_WEBHOOK_URL' => 'https://example.com/webhooks')
                                        .except('CAREERPLUG_WEBHOOK_SECRET'))
        end

        it 'does not create a webhook' do
          expect do
            create(:partnership)
          end.not_to change(WebhookUrl, :count)
        end
      end

      context 'with only webhook secret set' do
        before do
          stub_const('ENV', ENV.to_hash.merge('CAREERPLUG_WEBHOOK_SECRET' => 'test-secret')
                                        .except('CAREERPLUG_WEBHOOK_URL'))
        end

        it 'does not create a webhook' do
          expect do
            create(:partnership)
          end.not_to change(WebhookUrl, :count)
        end
      end
    end
  end

  describe '#create_careerplug_webhook' do
    before do
      stub_const('ENV', ENV.to_hash.merge(
                          'CAREERPLUG_WEBHOOK_URL' => 'https://example.com/webhooks',
                          'CAREERPLUG_WEBHOOK_SECRET' => 'manual-secret'
                        ))
    end

    context 'when called manually' do
      it 'is idempotent' do
        partnership = create(:partnership)
        initial_count = partnership.webhook_urls.count

        partnership.create_careerplug_webhook

        expect(partnership.webhook_urls.count).to eq(initial_count)
      end
    end
  end
end
