# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Abilities::TemplateConditions do
  let!(:account_group) { create(:account_group, :with_user_and_folder) }
  let!(:global_account_group) { create(:account_group, :with_user_and_folder) }
  let!(:account) { create(:account, :with_user_and_folder, account_group: account_group) }

  before do
    allow(ExportLocation).to receive(:global_account_group_id).and_return(global_account_group.id)
  end

  def create_account_template
    create(:template, account: account, author: account.users.first, folder: account.template_folders.first)
  end

  def create_account_group_template
    create(
      :template,
      account: nil,
      account_group: account_group,
      author: account_group.users.first,
      folder: account_group.template_folders.first
    )
  end

  def create_global_template
    create(
      :template,
      account: nil,
      account_group: global_account_group,
      author: global_account_group.users.first,
      folder: global_account_group.template_folders.first
    )
  end

  describe '.collection' do
    context 'with account user' do
      it 'returns templates accessible to account user' do
        user = account.users.first
        create_account_template
        create_account_group_template
        create_global_template

        templates = described_class.collection(user)

        expect(templates.count).to be >= 3
      end
    end

    context 'with account group user' do
      it 'returns templates accessible to account group user' do
        account_group_user = account_group.users.first
        create_account_group_template
        create_global_template

        templates = described_class.collection(account_group_user)

        expect(templates.count).to be >= 2
      end
    end
  end

  describe '.entity' do
    it 'allows global template access for any user' do
      global_template = create_global_template
      user = account.users.first

      expect(described_class.entity(global_template, user: user)).to be true
    end

    it 'allows account group template access for users in same account group' do
      account_group_template = create_account_group_template
      user = account.users.first

      expect(described_class.entity(account_group_template, user: user)).to be true
    end

    it 'denies account group template access for users in different account group' do
      account_group_template = create_account_group_template
      other_user = create(:user)

      expect(described_class.entity(account_group_template, user: other_user)).to be false
    end

    it 'allows account template access for same account user' do
      account_template = create_account_template
      user = account.users.first

      expect(described_class.entity(account_template, user: user)).to be true
    end

    it 'denies account template access for different account user' do
      account_template = create_account_template
      other_user = create(:user)

      expect(described_class.entity(account_template, user: other_user)).to be false
    end
  end
end
