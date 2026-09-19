# frozen_string_literal: true

RSpec.describe 'Template Builder' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, attachment_count: 3, except_field_types: %w[phone payment]) }

  before do
    sign_in(author)
  end

  context 'when manage template documents' do
    before do
      visit edit_template_path(template)
    end

    it 'replaces the document' do
      doc = find("div[id='documents_container'] div[data-document-uuid='#{template.schema[1]['attachment_uuid']}'")
      doc.click

      expect do
        doc.find('.replace-document-button').click
        doc.find('.replace-document-button input[type="file"]', visible: false)
           .attach_file(Rails.root.join('spec/fixtures/sample-image.png'))

        page.driver.wait_for_network_idle
      end.to change { template.documents.count }.by(1)

      expect(page).to have_content('sample-image')
      expect(page).to have_css('#upload_success_toast', text: 'Document uploaded successfully')
      expect(page).to have_css('#upload_success_toast[role="status"][aria-live="polite"]')
    end
  end

  context 'when uploading to an empty template' do
    let(:template) { create(:template, account:, author:, attachment_count: 0) }

    before do
      visit edit_template_path(template)
    end

    it 'shows a success toast after the first document upload' do
      expect(page).to have_css('#document_dropzone')

      expect do
        find('#document_dropzone input[type="file"]', visible: false)
          .attach_file(Rails.root.join('spec/fixtures/sample-image.png'))

        page.driver.wait_for_network_idle
      end.to change { template.reload.documents.count }.by(1)

      expect(page).to have_content('sample-image')
      expect(page).to have_css('#upload_success_toast', text: 'Document uploaded successfully')
      expect(page).to have_css('#upload_success_toast[role="status"][aria-live="polite"]')
    end
  end

  context 'when uploading a PDF over the page limit' do
    let(:template) { create(:template, account:, author:, attachment_count: 0) }
    let(:oversize_pdf_path) { Rails.root.join('tmp/oversize-document-130-pages.pdf') }

    before do
      doc = HexaPDF::Document.new
      130.times { doc.pages.add([0, 0, 612, 792]) }
      doc.write(oversize_pdf_path.to_s)

      visit edit_template_path(template)
    end

    after do
      # Drain trailing requests from the heavy page so they can't race the next example's one-shot test login.
      page.driver.wait_for_network_idle
      FileUtils.rm_f(Rails.root.join('tmp/oversize-document-130-pages.pdf'))
    end

    it 'blocks the upload and shows best-practices guidance' do
      expect(page).to have_css('#document_dropzone')

      expect do
        find('#document_dropzone input[type="file"]', visible: false).attach_file(oversize_pdf_path)

        page.driver.wait_for_network_idle
      end.not_to(change { template.reload.documents.count })

      expect(page).to have_css('#page_limit_modal[role="status"][aria-live="polite"]', text: /split/i)
      expect(page).to have_css('#page_limit_modal', text: '120')
    end
  end

  context 'when uploading a PDF under the page limit' do
    let(:template) { create(:template, account:, author:, attachment_count: 0) }

    before do
      visit edit_template_path(template)
    end

    it 'allows the upload without showing the page-limit modal' do
      expect(page).to have_css('#document_dropzone')

      expect do
        find('#document_dropzone input[type="file"]', visible: false)
          .attach_file(Rails.root.join('spec/fixtures/sample-document.pdf'))

        page.driver.wait_for_network_idle
      end.to change { template.reload.documents.count }.by(1)

      expect(page).to have_no_css('#page_limit_modal')
    end
  end

  context 'when uploading an encrypted PDF' do
    let(:template) { create(:template, account:, author:, attachment_count: 0) }
    let(:password) { 'docuseal-spec-password' }
    let(:encrypted_pdf_path) { Rails.root.join('tmp/encrypted-document.pdf') }

    before do
      doc = HexaPDF::Document.new
      doc.pages.add([0, 0, 612, 792])
      doc.encrypt(user_password: password, owner_password: password)
      doc.write(encrypted_pdf_path.to_s)

      visit edit_template_path(template)
    end

    after do
      FileUtils.rm_f(Rails.root.join('tmp/encrypted-document.pdf'))
    end

    it 'skips the page-limit guard and preserves the password-prompt flow' do
      expect(page).to have_css('#document_dropzone')

      expect do
        accept_prompt(with: password, wait: 10) do
          find('#document_dropzone input[type="file"]', visible: false).attach_file(encrypted_pdf_path)
        end

        page.driver.wait_for_network_idle
      end.to change { template.reload.documents.count }.by(1)

      expect(page).to have_no_css('#page_limit_modal')
    end
  end

  context 'when clicking the preview button' do
    it 'redirects to the template form page' do
      visit edit_template_path(template)
      click_on 'Preview'
      expect(page).to have_current_path("/templates/#{template.id}/form")
    end
  end
end
