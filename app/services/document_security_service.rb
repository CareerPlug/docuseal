# frozen_string_literal: true

require 'aws-sdk-cloudfront'

# Service for handling secure document access with CloudFront signed URLs
# Reuses same infrastructure and key pairs as ATS
class DocumentSecurityService
  # Raised when a secure URL cannot be generated. Callers must surface this as
  # an error response -- never fall back to attachment.url: a presigned S3 URL
  # for the secured bucket is rejected with a raw S3 AccessDenied XML page in
  # the user's browser (CP-15418).
  class SigningError < StandardError; end

  class << self
    # @param attachment [ActiveStorage::Attachment] The attachment to generate URL for
    # @param expires_in [ActiveSupport::Duration] How long the URL should be valid
    # @return [String] Signed CloudFront URL
    # @raise [SigningError] when CloudFront is not configured or signing fails
    def signed_url_for(attachment, expires_in: 1.hour)
      unless cloudfront_configured?
        raise SigningError,
              'CloudFront is not configured (CF_URL/CF_KEY_PAIR_ID/SECURE_ATTACHMENT_PRIVATE_KEY)'
      end

      cloudfront_signer.signed_url(build_cloudfront_url(attachment), expires: expires_in.from_now.to_i)
    rescue SigningError
      raise
    rescue StandardError => e
      raise SigningError, "CloudFront signing failed: #{e.class}: #{e.message}"
    end

    private

    def cloudfront_configured?
      cloudfront_base_url.present? &&
        cloudfront_key_pair_id.present? &&
        cloudfront_private_key.present?
    end

    def cloudfront_signer
      @cloudfront_signer ||= Aws::CloudFront::UrlSigner.new(
        key_pair_id: cloudfront_key_pair_id,
        private_key: cloudfront_private_key
      )
    end

    def build_cloudfront_url(attachment)
      key = ensure_docuseal_prefix(attachment.blob.key)
      "#{cloudfront_base_url}/#{encode_path_segments(key)}?#{build_query_params(attachment)}"
    end

    # CloudFront validates the signature against the exact URL the client
    # requests. Secured blob keys embed the original filename verbatim
    # ("docuseal/<uuid>/<filename>"), and browsers percent-encode characters
    # like spaces before sending, so a signature over the raw key never
    # matches the request (CP-15418). Encode each segment individually so
    # "/" separators survive; strict RFC 3986 encoding keeps unreserved
    # characters literal, so already-safe keys are not double-encoded.
    def encode_path_segments(key)
      key.split('/').map { |segment| ERB::Util.url_encode(segment) }.join('/')
    end

    def ensure_docuseal_prefix(s3_key)
      s3_key.start_with?('docuseal/') ? s3_key : "docuseal/#{s3_key}"
    end

    def build_query_params(attachment)
      filename = attachment.blob.filename.to_s.presence || 'download.pdf'

      {
        'response-content-disposition' => content_disposition_for(filename),
        'response-content-type' => attachment.blob.content_type
      }.to_query
    end

    def content_disposition_for(filename)
      # RFC 6266 with RFC 5987 encoding for international characters
      rfc5987_encoded = CGI.escape(filename)
      "inline; filename=\"#{filename}\"; filename*=UTF-8''#{rfc5987_encoded}"
    end

    def cloudfront_base_url
      @cloudfront_base_url ||= ENV.fetch('CF_URL', nil)
    end

    def cloudfront_key_pair_id
      @cloudfront_key_pair_id ||= ENV.fetch('CF_KEY_PAIR_ID', nil)
    end

    def cloudfront_private_key
      @cloudfront_private_key ||= ENV.fetch('SECURE_ATTACHMENT_PRIVATE_KEY', nil)
    end
  end
end
