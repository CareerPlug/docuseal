# frozen_string_literal: true

require 'aws-sdk-secretsmanager'

# Load CloudFront private key from AWS Secrets Manager (same as ATS)
# Configuration loaded from environment variables (set in cpdocuseal deployment)
key_secret = ENV.fetch('CF_KEY_SECRET', nil)

if key_secret.present?
  begin
    client = Aws::SecretsManager::Client.new
    response = client.get_secret_value(secret_id: key_secret)
    ENV['SECURE_ATTACHMENT_PRIVATE_KEY'] = response.secret_string
    Rails.logger.info('Successfully loaded CloudFront private key from Secrets Manager')
  rescue StandardError => e
    Rails.logger.error("Failed to load CloudFront private key: #{e.message}")
  end
end

# Fail loudly (but do not block boot) when secured-storage serving is not
# usable outside of local dev/test. Without these, every aws_s3_secured
# document raises DocumentSecurityService::SigningError, so completed-doc
# downloads from ATS fail. Mirrors careerplug_webhook_config.rb.
unless Rails.env.local?
  missing = %w[CF_URL CF_KEY_PAIR_ID SECURE_ATTACHMENT_PRIVATE_KEY].reject { |key| ENV[key].present? }

  unless missing.empty?
    message = "CloudFront secured-storage config missing in #{Rails.env}: #{missing.join(', ')}. " \
              'Signed document URLs for secured storage will fail until this is fixed.'
    Rails.logger.error("[secure_attachment] #{message}")
    Airbrake.notify(message)
  end
end
