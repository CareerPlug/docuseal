# frozen_string_literal: true

# == Schema Information
#
# Table name: template_folders
#
#  id               :bigint           not null, primary key
#  archived_at      :datetime
#  name             :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_group_id :bigint
#  account_id       :integer
#  author_id        :integer          not null
#
# Indexes
#
#  index_template_folders_on_account_group_id  (account_group_id)
#  index_template_folders_on_account_id        (account_id)
#  index_template_folders_on_author_id         (author_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_group_id => account_groups.id)
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (author_id => users.id)
#
class TemplateFolder < ApplicationRecord
  DEFAULT_NAME = 'Default'

  belongs_to :author, class_name: 'User'
  belongs_to :account, optional: true
  belongs_to :account_group, optional: true

  validate :must_belong_to_account_or_account_group

  has_many :templates, dependent: :destroy, foreign_key: :folder_id, inverse_of: :folder
  has_many :active_templates, -> { where(archived_at: nil) },
           class_name: 'Template', dependent: :destroy, foreign_key: :folder_id, inverse_of: :folder

  scope :active, -> { where(archived_at: nil) }

  def default?
    name == DEFAULT_NAME
  end

  private

  def must_belong_to_account_or_account_group
    if account.blank? && account_group.blank?
      errors.add(:base, 'Folder must belong to either an account or account group')
    elsif account.present? && account_group.present?
      errors.add(:base, 'Folder cannot belong to both account and account group')
    end
  end
end
