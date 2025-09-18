# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Templates::CloneToAccount do
  let!(:account_group) { create(:account_group, :with_user_and_folder) }
  let!(:target_account) { create(:account, :with_user, external_account_id: 12_345) }

  let(:account_group_user) { account_group.users.first }
  let(:account_group_folder) { account_group.template_folders.first }
  let(:author) { target_account.users.first }
  let(:source_template) do
    create(
      :template,
      account: nil,
      account_group: account_group,
      author: account_group_user,
      folder: account_group_folder
    )
  end

  describe '.call' do
    context 'with target_account parameter' do
      it 'creates a cloned template in the target account' do
        cloned_template = described_class.call(
          source_template,
          target_account: target_account,
          author: author,
          name: 'Cloned Template'
        )

        expect(cloned_template.account).to eq(target_account)
        expect(cloned_template.author).to eq(author)
        expect(cloned_template.name).to eq('Cloned Template')
        expect(cloned_template.account_group_id).to be_nil
      end

      it 'clears template_accesses' do
        # Add some template accesses to the original
        create(:template_access, template: source_template, user: author)

        cloned_template = described_class.call(
          source_template,
          target_account: target_account,
          author: author
        )

        expect(cloned_template.template_accesses).to be_empty
      end

      it 'preserves template structure' do
        cloned_template = described_class.call(
          source_template,
          target_account: target_account,
          author: author
        )

        expect(cloned_template.submitters.size).to eq(source_template.submitters.size)
        expect(cloned_template.submitters.first['name']).to eq(source_template.submitters.first['name'])
        expect(cloned_template.fields.size).to eq(source_template.fields.size)
        expect(cloned_template.schema.size).to eq(source_template.schema.size)
      end
    end

    context 'with external_account_id parameter' do
      let!(:external_test_account) { create(:account, :with_user, external_account_id: 67_890) }
      let(:external_test_user) { external_test_account.users.first }

      it 'creates a cloned template when user has access' do
        cloned_template = described_class.call(
          source_template,
          external_account_id: 67_890,
          current_user: external_test_user,
          author: external_test_user,
          name: 'API Cloned Template'
        )

        expect(cloned_template.account).to eq(external_test_account)
        expect(cloned_template.name).to eq('API Cloned Template')
      end

      it 'raises error when user lacks access' do
        other_user = create(:user)

        expect do
          described_class.call(
            source_template,
            external_account_id: 67_890,
            current_user: other_user,
            author: other_user
          )
        end.to raise_error(ArgumentError, 'Unauthorized access to target account')
      end

      it 'raises error when account not found' do
        expect do
          described_class.call(
            source_template,
            external_account_id: 99_999,
            current_user: external_test_user,
            author: external_test_user
          )
        end.to raise_error(ActiveRecord::RecordNotFound, 'Account not found')
      end

      it 'raises error when current_user not provided' do
        expect do
          described_class.call(
            source_template,
            external_account_id: 67_890,
            author: external_test_user
          )
        end.to raise_error(ArgumentError, 'current_user required when using external_account_id')
      end
    end

    context 'with invalid parameters' do
      it 'raises error when neither target_account nor external_account_id provided' do
        expect do
          described_class.call(source_template, author: author)
        end.to raise_error(ArgumentError, 'Either target_account or external_account_id must be provided')
      end
    end

    context 'with non-account-group template' do
      let(:regular_template) { create(:template, account: target_account, author: author) }

      it 'raises ArgumentError' do
        expect do
          described_class.call(
            regular_template,
            target_account: target_account,
            author: author
          )
        end.to raise_error(ArgumentError, 'Template must be an account group template')
      end
    end
  end
end
