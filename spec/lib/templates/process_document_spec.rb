# frozen_string_literal: true

describe Templates::ProcessDocument do
  describe '.generate_pdf_preview_from_file' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account:) }
    let(:template) { create(:template, account:, author: user, attachment_count: 0) }
    let(:attachment) do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: Rails.root.join('spec/fixtures/sample-document.pdf').open,
        filename: 'sample-document.pdf',
        content_type: 'application/pdf'
      )
      ActiveStorage::Attachment.create!(blob: blob, name: :documents, record: template)
    end
    let(:file_path) { ActiveStorage::Blob.service.path_for(attachment.key) }

    it 'saves the preview blob under a filename the PreviewDocumentPageController cache lookup matches' do
      described_class.generate_pdf_preview_from_file(attachment, file_path, 0)

      cached = attachment.preview_images.joins(:blob)
                         .find_by(blob: { filename: ['0.png', '0.jpg'] })

      expect(cached).not_to be_nil
    end
  end
end
