# frozen_string_literal: true

namespace :careerplug do
  desc 'Alert (via Airbrake) when an ATS WebhookUrl is missing or ATS delivery fails'
  task check_webhooks: :environment do
    WebhookHealthCheck.report!
    WebhookHealthCheck.report_delivery!
  end
end
