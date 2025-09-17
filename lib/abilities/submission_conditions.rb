# frozen_string_literal: true

module Abilities
  # Provides authorization conditions for submission access control.
  # Only account users can access submissions (account_group users create templates).
  # Supports account group inheritance and global template access patterns.
  module SubmissionConditions
    module_function

    def collection(user, ability: nil)
      return [] if user.account_id.blank?

      submissions_for_user(user)
    end

    def entity(submission, user:, ability: nil)
      # Only account users can access submissions
      return false if user.account_id.blank?

      # User can access their own account's submissions
      return true if submission.account_id == user.account_id

      # User can access submissions from templates they have access to
      if submission.template_id.present?
        template = submission.template || Template.find_by(id: submission.template_id)
        return false unless template

        return true if user_can_access_template?(user, template)
      end
      false
    end

    def submissions_for_user(user)
      # For collection access, we still need to get all submissions the user can access
      # This is used by CanCan's accessible_by method for listing submissions
      accessible_template_ids = accessible_template_ids(user)

      Submission.where(
        'account_id = ? OR template_id IN (?)',
        user.account_id,
        accessible_template_ids
      )
    end

    def accessible_template_ids(user)
      template_ids = []

      # Add templates from user's account group (inheritance)
      if user.account.account_group_id.present?
        template_ids += Template.where(account_group_id: user.account.account_group_id).pluck(:id)
      end

      # Add templates from global account group (accessible to everyone)
      if ExportLocation.global_account_group_id.present?
        template_ids += Template.where(account_group_id: ExportLocation.global_account_group_id).pluck(:id)
      end

      template_ids.uniq
    end

    def user_can_access_template?(user, template)
      return true if inherited_account_group_template?(user, template)
      return true if global_template_accessible?(template)

      false
    end

    def inherited_account_group_template?(user, template)
      user.account.account_group_id.present? &&
        template.account_group_id == user.account.account_group_id
    end

    def global_template_accessible?(template)
      ExportLocation.global_account_group_id.present? &&
        template.account_group_id == ExportLocation.global_account_group_id
    end
  end
end
