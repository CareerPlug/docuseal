# frozen_string_literal: true

module Abilities
  # Provides authorization conditions for submission access control.
  # Only account users can access submissions (partnership users create templates).
  # Supports partnership inheritance and global template access patterns.
  module SubmissionConditions
    module_function

    def collection(user)
      return [] if user.account_id.blank?

      submissions_for_user(user)
    end

    def entity(submission, user:)
      # Only account users can access submissions
      return false if user.account_id.blank?

      # User can access their own account's submissions
      return true if submission.account_id == user.account_id

      if submission.template_id.present?
        template = submission.template || Template.find_by(id: submission.template_id)
        return false unless template

        return true if user_can_access_template?(user, template)
      end
      false
    end

    def submissions_for_user(user)
      accessible_template_ids = accessible_template_ids(user)

      Submission.where(
        'submissions.account_id = ? OR submissions.template_id IN (?)',
        user.account_id,
        accessible_template_ids
      )
    end

    def accessible_template_ids(user)
      template_ids = []

      # Add templates from user's partnership (inheritance)
      if user.account.partnership_id.present?
        template_ids += Template.where(partnership_id: user.account.partnership_id).pluck(:id)
      end

      # Add templates from global partnership (accessible to everyone)
      if ExportLocation.global_partnership_id.present?
        template_ids += Template.where(partnership_id: ExportLocation.global_partnership_id).pluck(:id)
      end

      template_ids.uniq
    end

    def user_can_access_template?(user, template)
      return true if inherited_partnership_template?(user, template)
      return true if global_template_accessible?(template)

      false
    end

    def inherited_partnership_template?(user, template)
      user.account.partnership_id.present? &&
        template.partnership_id == user.account.partnership_id
    end

    def global_template_accessible?(template)
      ExportLocation.global_partnership_id.present? &&
        template.partnership_id == ExportLocation.global_partnership_id
    end
  end
end
