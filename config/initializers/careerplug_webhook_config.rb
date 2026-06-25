# frozen_string_literal: true

# Fail loudly (but do not block boot) if CareerPlug webhook configuration is
# missing outside of local dev/test. Without these env vars, the Account/
# Partnership create callbacks skip WebhookUrl creation, which leaves ATS form
# submissions stuck at "assigned" forever. A missing config should be impossible
# to miss on deploy, so this logs a prominent error and reports to error
# tracking. Non-blocking so that console/migrate access remains available for
# recovery.
unless Rails.env.local?
  missing = %w[CAREERPLUG_WEBHOOK_URL CAREERPLUG_WEBHOOK_SECRET].reject { |key| ENV[key].present? }

  unless missing.empty?
    message = "CareerPlug webhook config missing in #{Rails.env}: #{missing.join(', ')}. " \
              'New accounts/partnerships will not get webhooks until this is fixed.'
    Rails.logger.error("[careerplug_webhook_config] #{message}")
    Airbrake.notify(message)
  end
end
