# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DocumentSecurityService do
  let(:account) { create(:account) }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join('spec/fixtures/sample-document.pdf').open,
      filename: 'test-document.pdf',
      content_type: 'application/pdf'
    )
  end
  let(:attachment) do
    ActiveStorage::Attachment.create!(
      blob: blob,
      name: :documents,
      record: account
    )
  end

  before do
    ActiveStorage::Current.url_options = { host: 'test.example.com' }
  end

  describe '.signed_url_for' do
    context 'when CloudFront is not configured' do
      before do
        allow(ENV).to receive(:fetch).with('CF_URL', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('CF_KEY_PAIR_ID', nil).and_return(nil)
        allow(ENV).to receive(:fetch).with('SECURE_ATTACHMENT_PRIVATE_KEY', nil).and_return(nil)
      end

      it 'returns the regular attachment URL' do
        result = described_class.signed_url_for(attachment)
        expect(result).to eq(attachment.url)
      end
    end

    context 'when CloudFront is configured' do
      let(:cloudfront_url) { 'https://d123456.cloudfront.net' }
      let(:key_pair_id) { 'EXAMPLE_KEY' }
      let(:private_key) { 'fake-private-key-for-testing' }

      before do
        allow(ENV).to receive(:fetch).with('CF_URL', nil).and_return(cloudfront_url)
        allow(ENV).to receive(:fetch).with('CF_KEY_PAIR_ID', nil).and_return(key_pair_id)
        allow(ENV).to receive(:fetch).with('SECURE_ATTACHMENT_PRIVATE_KEY', nil).and_return(private_key)
      end

      after do
        # Clear memoized signer between examples
        described_class.instance_variable_set(:@cloudfront_signer, nil)
      end

      it 'generates a signed CloudFront URL' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
        allow(signer).to receive(:signed_url).and_return('https://signed-url.example.com')

        result = described_class.signed_url_for(attachment)

        expect(result).to eq('https://signed-url.example.com')
      end

      it 'includes Content-Disposition header in the URL' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
        expected_url_pattern = %r{
          #{Regexp.escape(cloudfront_url)}/docuseal/.*
          \?response-content-disposition=.*filename%3D%22test-document\.pdf%22.*
          &response-content-type=application%2Fpdf
        }x

        expect(signer).to receive(:signed_url) do |url, **_options|
          expect(url).to match(expected_url_pattern)
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(attachment)
      end

      it 'properly escapes special characters in filename' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)

        special_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('test'),
          filename: 'document with spaces & special.pdf',
          content_type: 'application/pdf'
        )
        special_attachment = ActiveStorage::Attachment.create!(
          blob: special_blob,
          name: :documents,
          record: account
        )

        expect(signer).to receive(:signed_url) do |url, **_options|
          expect(url).to include('response-content-disposition=')
          expect(url).to include(CGI.escape('document with spaces & special.pdf'))
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(special_attachment)
      end

      it 'uses default filename when blob filename is empty' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)

        empty_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('test'),
          filename: '',
          content_type: 'application/pdf'
        )
        empty_attachment = ActiveStorage::Attachment.create!(
          blob: empty_blob,
          name: :documents,
          record: account
        )

        expect(signer).to receive(:signed_url) do |url, **_options|
          decoded_url = CGI.unescape(url)
          expect(decoded_url).to include('filename="download.pdf"')
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(empty_attachment)
      end

      it 'adds docuseal prefix to S3 key if not present' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)

        expect(signer).to receive(:signed_url) do |url, **_options|
          expect(url).to include('/docuseal/')
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(attachment)
      end

      it 'does not duplicate docuseal prefix if already present' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
        allow(blob).to receive(:key).and_return('docuseal/existing-key')

        expect(signer).to receive(:signed_url) do |url, **_options|
          expect(url).to match(%r{/docuseal/[^/]})
          expect(url).not_to match(%r{/docuseal/docuseal/})
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(attachment)
      end

      it 'respects the expires_in parameter' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
        expires_time = 2.hours.from_now

        expect(signer).to receive(:signed_url) do |_url, **options|
          expect(options[:expires]).to be_within(1).of(expires_time.to_i)
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(attachment, expires_in: 2.hours)
      end

      it 'uses inline disposition in Content-Disposition header' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)

        expect(signer).to receive(:signed_url) do |url, **_options|
          decoded_url = CGI.unescape(url)
          expect(decoded_url).to include('inline; filename="test-document.pdf"')
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(attachment)
      end

      context 'when signing fails' do
        it 'logs the error' do
          signer = instance_double(Aws::CloudFront::UrlSigner)
          allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
          allow(signer).to receive(:signed_url).and_raise(StandardError.new('Signing failed'))

          expect(Rails.logger).to receive(:error).with(/Failed to generate signed URL: Signing failed/)
          described_class.signed_url_for(attachment)
        end

        it 'falls back to the regular attachment URL' do
          signer = instance_double(Aws::CloudFront::UrlSigner)
          allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
          allow(signer).to receive(:signed_url).and_raise(StandardError.new('Signing failed'))
          allow(Rails.logger).to receive(:error)

          result = described_class.signed_url_for(attachment)
          expect(result).to eq(attachment.url)
        end
      end
    end

    context 'with different content types' do
      let(:cloudfront_url) { 'https://d123456.cloudfront.net' }
      let(:key_pair_id) { 'EXAMPLE_KEY' }
      let(:private_key) { 'fake-private-key-for-testing' }

      before do
        allow(ENV).to receive(:fetch).with('CF_URL', nil).and_return(cloudfront_url)
        allow(ENV).to receive(:fetch).with('CF_KEY_PAIR_ID', nil).and_return(key_pair_id)
        allow(ENV).to receive(:fetch).with('SECURE_ATTACHMENT_PRIVATE_KEY', nil).and_return(private_key)
      end

      after do
        # Clear memoized signer between examples
        described_class.instance_variable_set(:@cloudfront_signer, nil)
      end

      it 'includes the correct content type for images' do
        signer = instance_double(Aws::CloudFront::UrlSigner)
        allow(Aws::CloudFront::UrlSigner).to receive(:new).and_return(signer)
        image_blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new('fake image'),
          filename: 'image.jpg',
          content_type: 'image/jpeg'
        )
        image_attachment = ActiveStorage::Attachment.create!(
          blob: image_blob,
          name: :documents,
          record: account
        )

        expect(signer).to receive(:signed_url) do |url, **_options|
          expect(url).to include('response-content-type=image%2Fjpeg')
          'https://signed-url.example.com'
        end

        described_class.signed_url_for(image_attachment)
      end
    end
  end
end
