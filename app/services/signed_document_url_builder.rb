# frozen_string_literal: true

class SignedDocumentUrlBuilder
  URL_EXPIRATION_TIME = 1.hour

  def initialize(submitter)
    @submitter = submitter
  end

  def call
    attachments.map do |attachment|
      {
        name: attachment.filename.to_s,
        url: generate_url(attachment),
        size_bytes: attachment.blob.byte_size,
        content_type: attachment.blob.content_type
      }
    end
  end

  private

  attr_reader :submitter

  def attachments
    Submitters.select_attachments_for_download(submitter)
  end

  def generate_url(attachment)
    if uses_secured_storage?(attachment)
      DocumentSecurityService.signed_url_for(attachment)
    else
      ActiveStorage::Blob.proxy_url(
        attachment.blob,
        expires_at: URL_EXPIRATION_TIME.from_now.to_i
      )
    end
  end

  def uses_secured_storage?(attachment)
    attachment.blob.service_name == 'aws_s3_secured'
  end
end
