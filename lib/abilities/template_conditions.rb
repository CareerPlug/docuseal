# frozen_string_literal: true

module Abilities
  module TemplateConditions
    module_function

    def collection(user, ability: nil)
      if user.account_id.present?
        account_templates = Template.where(account_id: user.account_id)
        template_ids = account_templates.pluck(:id)

        if user.account.account_group_id.present?
          template_ids += Template.where(account_group_id: user.account.account_group_id).pluck(:id)
        end

        if ExportLocation.global_account_group_id.present?
          template_ids += Template.where(account_group_id: ExportLocation.global_account_group_id).pluck(:id)
        end

        combined_templates = Template.where(id: template_ids.uniq)

        return combined_templates unless user.account.testing?

        shared_template_ids = TemplateSharing.where({ ability:,
                                                      account_id: [user.account_id, TemplateSharing::ALL_ID] }.compact)
                                             .pluck(:template_id)

        all_template_ids = (template_ids + shared_template_ids).uniq
        Template.where(id: all_template_ids)
      elsif user.account_group_id.present?
        template_ids = Template.where(account_group_id: user.account_group_id).pluck(:id)

        if ExportLocation.global_account_group_id.present?
          template_ids += Template.where(account_group_id: ExportLocation.global_account_group_id).pluck(:id)
        end

        Template.where(id: template_ids.uniq)
      else
        Template.none
      end
    end

    def entity(template, user:, ability: nil)
      # Allow access to templates without account/account_group restrictions
      return true if template.account_id.blank? && template.account_group_id.blank?

      # Handle account group templates
      if template.account_group_id.present?
        # Check direct account_group membership
        return true if template.account_group_id == user.account_group_id

        # Check if user's account belongs to the template's account_group
        return true if user.account_id.present? && user.account.account_group_id == template.account_group_id

        # Check if template belongs to global account group (accessible to all)
        return true if global_template?(template)

        return false
      end

      # Handle regular account templates
      return true if template.account_id == user.account_id

      # Check linked accounts and template sharings
      return false unless user.account&.linked_account_account
      return false if template.template_sharings.to_a.blank?

      template_sharing_accessible?(template, user, ability)
    end

    def global_template?(template)
      ExportLocation.global_account_group_id.present? &&
        template.account_group_id == ExportLocation.global_account_group_id
    end

    def template_sharing_accessible?(template, user, ability)
      account_ids = [user.account_id, TemplateSharing::ALL_ID]
      template.template_sharings.to_a.any? do |sharing|
        sharing.account_id.in?(account_ids) &&
          (ability.nil? || sharing.ability == 'manage' || sharing.ability == ability)
      end
    end
  end
end
