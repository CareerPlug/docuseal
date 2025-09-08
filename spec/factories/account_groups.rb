# frozen_string_literal: true

FactoryBot.define do
  factory :account_group do
    external_account_group_id { Faker::Alphanumeric.alphanumeric(number: 10) }
    name { Faker::Company.name }
  end
end
