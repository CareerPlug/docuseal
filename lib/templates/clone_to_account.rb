# frozen_string_literal: true

module Templates
  module CloneToAccount
    module_function

    # Clone an account group template to a specific account
    def call(original_template, target_account:, author:, external_id: nil, name: nil, folder_name: nil)
      unless original_template.account_group_id.present?
        raise ArgumentError, 'Template must be an account group template'
      end

      # Temporarily override the account to use target_account for cloning
      original_template.define_singleton_method(:account) { target_account }

      template = Templates::Clone.call(
        original_template,
        author: author,
        external_id: external_id,
        name: name,
        folder_name: folder_name
      )

      # Clear template_accesses since account group templates shouldn't copy user accesses
      template.template_accesses.clear

      template
    end
  end
end
