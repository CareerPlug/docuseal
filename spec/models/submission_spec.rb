# frozen_string_literal: true

# == Schema Information
#
# Table name: submissions
#
#  id                  :bigint           not null, primary key
#  approved_at         :datetime
#  archived_at         :datetime
#  expire_at           :datetime
#  name                :text
#  preferences         :text             not null
#  requires_approval   :boolean          default(FALSE), not null
#  slug                :string           not null
#  source              :string           not null
#  submitters_order    :string           not null
#  template_fields     :text
#  template_schema     :text
#  template_submitters :text
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :integer          not null
#  created_by_user_id  :integer
#  template_id         :integer
#
# Indexes
#
#  index_submissions_on_account_id_and_id                           (account_id,id)
#  index_submissions_on_account_id_and_template_id_and_id           (account_id,template_id,id) WHERE (archived_at IS NULL)
#  index_submissions_on_account_id_and_template_id_and_id_archived  (account_id,template_id,id) WHERE (archived_at IS NOT NULL)
#  index_submissions_on_created_by_user_id                          (created_by_user_id)
#  index_submissions_on_slug                                        (slug) UNIQUE
#  index_submissions_on_template_id                                 (template_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_user_id => users.id)
#  fk_rails_...  (template_id => templates.id)
#
RSpec.describe Submission do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) { create(:submission, template:, created_by_user: user) }

  describe '#template_signing_order' do
    it 'returns the submitters_order from template preferences' do
      template.update!(preferences: { 'submitters_order' => 'employee_then_manager' })
      expect(submission.template_signing_order).to eq('employee_then_manager')
    end

    it 'returns nil when template has no submitters_order preference' do
      template.update_column(:preferences, {})
      expect(submission.reload.template_signing_order).to be_nil
    end

    it 'returns nil when submission has no template' do
      submission.update!(template: nil)
      expect(submission.template_signing_order).to be_nil
    end
  end

  describe '#signing_order_enforced?' do
    it 'returns true for employee_then_manager' do
      template.update!(preferences: { 'submitters_order' => 'employee_then_manager' })
      expect(submission.signing_order_enforced?).to be true
    end

    it 'returns true for manager_then_employee' do
      template.update!(preferences: { 'submitters_order' => 'manager_then_employee' })
      expect(submission.signing_order_enforced?).to be true
    end

    it 'returns false for simultaneous' do
      template.update!(preferences: { 'submitters_order' => 'simultaneous' })
      expect(submission.signing_order_enforced?).to be false
    end

    it 'returns false for single_sided' do
      template.update!(preferences: { 'submitters_order' => 'single_sided' })
      expect(submission.signing_order_enforced?).to be false
    end
  end
end
