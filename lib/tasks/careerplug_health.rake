# frozen_string_literal: true

namespace :careerplug do
  desc 'Alert (via Airbrake) when an ATS-linked account/partnership has no ATS-pointed WebhookUrl'
  task check_webhooks: :environment do
    WebhookHealthCheck.report!
  end
end
