# frozen_string_literal: true

FactoryBot.define do
  factory :account_group do
    external_account_group_id { Faker::Number.unique.number(digits: 8) }
    name { Faker::Company.name }

    trait :with_user do
      after(:create) do |account_group|
        create(:user, account_group: account_group, account: nil)
      end
    end

    trait :with_folder do
      after(:create) do |account_group|
        user = account_group.users.first || create(:user, account_group: account_group, account: nil)
        create(:template_folder, account: nil, account_group: account_group, author: user)
      end
    end

    trait :with_user_and_folder do
      after(:create) do |account_group|
        user = create(:user, account_group: account_group, account: nil)
        create(:template_folder, account: nil, account_group: account_group, author: user)
      end
    end
  end
end
