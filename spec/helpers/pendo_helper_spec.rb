# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PendoHelper, type: :helper do
  describe '#insert_pendo?' do
    it 'is false when PENDO_API_KEY is blank' do
      ENV.delete('PENDO_API_KEY')
      expect(helper.insert_pendo?).to be(false)
    end

    it 'is true when PENDO_API_KEY is present' do
      ENV['PENDO_API_KEY'] = 'test-key'
      expect(helper.insert_pendo?).to be(true)
    ensure
      ENV.delete('PENDO_API_KEY')
    end

    it 'is false while impersonating' do
      ENV['PENDO_API_KEY'] = 'test-key'
      user = build(:user)
      without_partial_double_verification do
        allow(helper).to receive_messages(current_user: user, true_user: build(:user))
      end
      expect(helper.insert_pendo?).to be(false)
    ensure
      ENV.delete('PENDO_API_KEY')
    end
  end

  describe '#pendo_initialize_payload' do
    it 'is empty when not signed in' do
      allow(helper).to receive(:signed_in?).and_return(false)
      expect(helper.pendo_initialize_payload).to eq({})
    end

    it 'uses ATS external ids when present' do
      account = build(:account, external_account_id: 99, name: 'Acme')
      user = build(:user, account:, external_user_id: 42, email: 'a@example.com', id: 7)
      without_partial_double_verification do
        allow(helper).to receive_messages(signed_in?: true, current_user: user, current_account: account)
      end

      expect(helper.pendo_initialize_payload).to eq(
        visitor: { id: 42, email: 'a@example.com' },
        account: { id: 99, name: 'Acme' }
      )
    end

    it 'omits account for partnership users with no account' do
      user = build(:user, :with_partnership, external_user_id: 42, email: 'p@example.com', id: 8)
      without_partial_double_verification do
        allow(helper).to receive_messages(signed_in?: true, current_user: user, current_account: nil)
      end

      payload = helper.pendo_initialize_payload
      expect(payload[:visitor][:id]).to eq(42)
      expect(payload).not_to have_key(:account)
    end

    it 'falls back to DocuSeal ids when external ids are nil' do
      account = build(:account, external_account_id: nil, name: 'Local', id: 3)
      user = build(:user, account:, external_user_id: nil, email: 'l@example.com', id: 5)
      without_partial_double_verification do
        allow(helper).to receive_messages(signed_in?: true, current_user: user, current_account: account)
      end

      expect(helper.pendo_initialize_payload[:visitor][:id]).to eq(5)
      expect(helper.pendo_initialize_payload[:account][:id]).to eq(3)
    end
  end
end
