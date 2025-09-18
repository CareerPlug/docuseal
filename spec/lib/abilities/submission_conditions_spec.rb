# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Abilities::SubmissionConditions do
  let(:account_group) { create(:account_group) }
  let(:account) { create(:account, account_group: account_group) }
  let(:user) { create(:user, account: account) }
  let(:account_group_user) { create(:user, account_group: account_group, account: nil) }

  before do
    allow(ExportLocation).to receive(:global_account_group_id).and_return(nil)
  end

  describe '.collection' do
    it 'returns empty array for account_group users' do
      expect(described_class.collection(account_group_user)).to eq([])
    end
  end

  describe '.entity' do
    it 'returns false for account_group users' do
      submission = build(:submission, account: account)
      expect(described_class.entity(submission, user: account_group_user)).to be false
    end

    it 'returns true for own account submissions' do
      submission = build(:submission, account: account)
      expect(described_class.entity(submission, user: user)).to be true
    end

    it 'returns true when user account group matches template account group' do
      template = instance_double(Template, account_group_id: account_group.id)
      submission = build(:submission, account: create(:account), template: template, template_id: 123)
      allow(Template).to receive(:find_by).with(id: 123).and_return(template)

      expect(described_class.entity(submission, user: user)).to be true
    end

    it 'returns true for global template submissions' do
      global_account_group = create(:account_group)
      allow(ExportLocation).to receive(:global_account_group_id).and_return(global_account_group.id)

      template = instance_double(Template, account_group_id: global_account_group.id)
      submission = build(:submission, account: create(:account), template: template, template_id: 123)
      allow(Template).to receive(:find_by).with(id: 123).and_return(template)

      expect(described_class.entity(submission, user: user)).to be true
    end

    it 'returns false for inaccessible template submissions' do
      other_account_group = create(:account_group)
      template = instance_double(Template, account_group_id: other_account_group.id)
      submission = build(:submission, account: create(:account), template: template, template_id: 123)
      allow(Template).to receive(:find_by).with(id: 123).and_return(template)

      expect(described_class.entity(submission, user: user)).to be false
    end

    it 'returns false when template is not found' do
      submission = build(:submission, account: create(:account), template: nil, template_id: 999)
      allow(Template).to receive(:find_by).with(id: 999).and_return(nil)

      expect(described_class.entity(submission, user: user)).to be false
    end

    it 'returns false when submission has no template' do
      submission = build(:submission, account: create(:account), template: nil, template_id: nil)

      expect(described_class.entity(submission, user: user)).to be false
    end
  end
end
