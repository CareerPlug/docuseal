# frozen_string_literal: true

RSpec.describe 'PDF Signature Settings' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before do
    sign_in(user)
    visit settings_esign_path
  end

  it 'shows verify signed PDF page' do
    expect(page).to have_content('PDF Signature')
    expect(page).to have_content('Upload signed PDF file to validate its signature')
    expect(page).to have_content('Verify Signed PDF')
    expect(page).to have_content('Click to upload or drag and drop files')
  end

  context 'when verifying a PDF over the template page limit' do
    let(:oversize_pdf_path) { Rails.root.join('tmp/oversize-esign-130-pages.pdf') }

    before do
      account.encrypted_configs.create!(
        key: EncryptedConfig::ESIGN_CERTS_KEY,
        value: GenerateCertificate.call.transform_values(&:to_pem)
      )

      doc = HexaPDF::Document.new
      130.times { doc.pages.add([0, 0, 612, 792]) }
      doc.write(oversize_pdf_path.to_s)
    end

    after do
      page.driver.wait_for_network_idle
      FileUtils.rm_f(Rails.root.join('tmp/oversize-esign-130-pages.pdf'))
    end

    it 'accepts the PDF without the page-limit guard' do
      expect(page).to have_css('#file', visible: false)

      find('#file', visible: false).attach_file(oversize_pdf_path)

      expect(page).to have_content('There are no signatures', wait: 10)
      expect(page).to have_no_css('.page-limit-message')
    end
  end
end
