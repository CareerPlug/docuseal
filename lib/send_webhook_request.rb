# frozen_string_literal: true

module SendWebhookRequest
  USER_AGENT = 'DocuSeal.com Webhook'

  LOCALHOSTS = %w[0.0.0.0 127.0.0.1 localhost].freeze

  HttpsError = Class.new(StandardError)
  LocalhostError = Class.new(StandardError)

  module_function

  def call(webhook_url, event_type:, data:)
    uri = begin
      URI(webhook_url.url)
    rescue URI::Error
      Addressable::URI.parse(webhook_url.url).normalize
    end

    if Docuseal.multitenant?
      raise HttpsError, 'Only HTTPS is allowed.' if uri.scheme != 'https' &&
                                                    !AccountConfig.exists?(key: :allow_http,
                                                                           account_id: webhook_url.account_id)
      raise LocalhostError, "Can't send to localhost." if uri.host.in?(LOCALHOSTS)
    end

    response = post(webhook_url, uri, event_type: event_type, data: data)
  rescue Faraday::Error => e
    record_delivery(event_type, nil)
    Rails.logger.error("Webhook transport error (#{event_type}): #{e.class} #{e.message}")
    Airbrake.notify("DocuSeal outbound webhook transport error (#{event_type}): #{e.class}")
    nil
  else
    record_delivery(event_type, response.status.to_i)
    response
  end

  def post(webhook_url, uri, event_type:, data:)
    Faraday.post(uri) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.headers['User-Agent'] = USER_AGENT

      # Send webhook secret headers from the configured secret hash
      webhook_url.secret&.each do |header_name, header_value|
        req.headers[header_name] = header_value
      end

      req.body = {
        event_type: event_type,
        timestamp: Time.current,
        data: data
      }.to_json

      req.options.read_timeout = 8
      req.options.open_timeout = 8
    end
  end

  # Records delivery outcome as New Relic custom metrics so non-2xx rates and
  # transport failures (previously swallowed silently to nil) are visible on a
  # dashboard. No-op when the New Relic agent isn't loaded.
  def record_delivery(event_type, status)
    return unless defined?(::NewRelic::Agent)

    bucket = status&.between?(200, 299) ? 'success' : 'failure'
    ::NewRelic::Agent.record_metric("DocuSeal/Webhook/#{event_type}/#{bucket}", 1)
    ::NewRelic::Agent.record_metric("DocuSeal/Webhook/total/#{bucket}", 1)
  end
end
