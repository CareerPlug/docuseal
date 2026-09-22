# frozen_string_literal: true

RSpec.describe 'Dashboard Page' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before do
    sign_in(user)
  end

  context 'when are no templates' do
    it 'shows empty state' do
      skip 'implementation needed'
      visit root_path

      expect(page).to have_link('Create', href: new_template_path)
    end
  end

  context 'when there are templates' do
    let!(:authors) { create_list(:user, 5, account:) }
    let!(:templates) { authors.map { |author| create(:template, account:, author:) } }
    let!(:other_template) { create(:template, account: create(:user).account) }

    before do
      visit root_path
    end

    it 'shows the list of templates' do
      skip 'implementation needed'
      templates.each do |template|
        expect(page).to have_content(template.name)
        expect(page).to have_content(template.author.full_name)
      end

      expect(page).to have_content('Templates')
      expect(page).to have_no_content(other_template.name)
      expect(page).to have_link('Create', href: new_template_path)
    end

    it 'initializes the template creation process' do
      skip 'implementation needed'
      click_link 'Create'

      within('#modal') do
        fill_in 'template[name]', with: 'New Template'

        expect do
          click_button 'Create'
        end.to change(Template, :count).by(1)

        expect(page).to have_current_path(edit_template_path(Template.last), ignore_query: true)
      end
    end

    it 'searches be submitter email' do
      skip 'implementation needed'
      submission = create(:submission, :with_submitters, template: templates[0])
      submitter = submission.submitters.first

      SearchEntries.reindex_all

      visit root_path(q: submitter.email)

      expect(page).to have_content('Templates not Found')
      expect(page).to have_content('Submissions')
      expect(page).to have_content(submitter.name)
    end
  end

  context 'when uploading a PDF over the page limit via the dropzone' do
    let(:oversize_pdf_path) { Rails.root.join('tmp/oversize-dashboard-130-pages.pdf') }

    before do
      doc = HexaPDF::Document.new
      130.times { doc.pages.add([0, 0, 612, 792]) }
      doc.write(oversize_pdf_path.to_s)

      visit root_path
    end

    after do
      # Drain trailing requests (the blocked-attempt metrics POST) so they can't race the next example's one-shot test login.
      page.driver.wait_for_network_idle
      FileUtils.rm_f(Rails.root.join('tmp/oversize-dashboard-130-pages.pdf'))
    end

    it 'blocks the upload and shows best-practices guidance' do
      expect(page).to have_css('#file_dropzone_input', visible: false)

      find('#file_dropzone_input', visible: false).attach_file(oversize_pdf_path)

      expect(page).to have_css('.page-limit-message[role="status"][aria-live="polite"]', text: /split/i)
      expect(page).to have_css('.page-limit-message', text: '120')
      expect(account.templates.count).to eq(0)
    end
  end

  context 'when uploading a PDF under the page limit via the dropzone' do
    before do
      visit root_path
    end

    after do
      page.driver.wait_for_network_idle
    end

    it 'allows the upload without showing the page-limit message' do
      expect(page).to have_css('#file_dropzone_input', visible: false)

      find('#file_dropzone_input', visible: false).attach_file(Rails.root.join('spec/fixtures/sample-document.pdf'))

      expect(page).to have_current_path(%r{/templates/\d+/edit}, wait: 10)
      expect(account.templates.count).to eq(1)
      expect(page).to have_no_css('.page-limit-message')
    end
  end

  context 'when uploading an encrypted PDF via the dropzone' do
    let(:password) { 'docuseal-spec-password' }
    let(:encrypted_pdf_path) { Rails.root.join('tmp/encrypted-dashboard-document.pdf') }

    before do
      doc = HexaPDF::Document.new
      doc.pages.add([0, 0, 612, 792])
      doc.encrypt(user_password: password, owner_password: password)
      doc.write(encrypted_pdf_path.to_s)

      visit root_path
    end

    after do
      page.driver.wait_for_network_idle
      FileUtils.rm_f(Rails.root.join('tmp/encrypted-dashboard-document.pdf'))
    end

    it 'skips the page-limit guard and preserves the password-prompt flow' do
      expect(page).to have_css('#file_dropzone_input', visible: false)

      accept_prompt(with: password, wait: 10) do
        find('#file_dropzone_input', visible: false).attach_file(encrypted_pdf_path)
      end

      expect(page).to have_current_path(%r{/templates/\d+/edit}, wait: 10)
      # Pre-existing dashboard behavior: the first attempt saves a template before the password failure, the password resubmit saves a second one.
      expect(account.templates.count).to eq(2)
      expect(page).to have_no_css('.page-limit-message')
    end
  end

  context 'when uploading a PDF over the page limit via the upload button' do
    let(:oversize_pdf_path) { Rails.root.join('tmp/oversize-dashboard-130-pages.pdf') }

    before do
      doc = HexaPDF::Document.new
      130.times { doc.pages.add([0, 0, 612, 792]) }
      doc.write(oversize_pdf_path.to_s)

      visit root_path
    end

    after do
      page.driver.wait_for_network_idle
      FileUtils.rm_f(Rails.root.join('tmp/oversize-dashboard-130-pages.pdf'))
    end

    it 'blocks the upload and shows best-practices guidance' do
      expect(page).to have_css('#upload_template', visible: false)

      find('#upload_template', visible: false).attach_file(oversize_pdf_path)

      expect(page).to have_css('.page-limit-message[role="status"][aria-live="polite"]', text: /split/i)
      expect(page).to have_css('.page-limit-message', text: '120')
      expect(account.templates.count).to eq(0)
    end
  end

  context 'when uploading a PDF under the page limit via the upload button' do
    before do
      visit root_path
    end

    after do
      page.driver.wait_for_network_idle
    end

    it 'allows the upload without showing the page-limit message' do
      expect(page).to have_css('#upload_template', visible: false)

      find('#upload_template', visible: false).attach_file(Rails.root.join('spec/fixtures/sample-document.pdf'))

      expect(page).to have_current_path(%r{/templates/\d+/edit}, wait: 10)
      expect(account.templates.count).to eq(1)
      expect(page).to have_no_css('.page-limit-message')
    end
  end

  context 'when uploading an encrypted PDF via the upload button' do
    let(:password) { 'docuseal-spec-password' }
    let(:encrypted_pdf_path) { Rails.root.join('tmp/encrypted-dashboard-document.pdf') }

    before do
      doc = HexaPDF::Document.new
      doc.pages.add([0, 0, 612, 792])
      doc.encrypt(user_password: password, owner_password: password)
      doc.write(encrypted_pdf_path.to_s)

      visit root_path
    end

    after do
      page.driver.wait_for_network_idle
      FileUtils.rm_f(Rails.root.join('tmp/encrypted-dashboard-document.pdf'))
    end

    it 'skips the page-limit guard and preserves the password-prompt flow' do
      expect(page).to have_css('#upload_template', visible: false)

      accept_prompt(with: password, wait: 10) do
        find('#upload_template', visible: false).attach_file(encrypted_pdf_path)
      end

      expect(page).to have_current_path(%r{/templates/\d+/edit}, wait: 10)
      # Pre-existing dashboard behavior: the first attempt saves a template before the password failure, the password resubmit saves a second one.
      expect(account.templates.count).to eq(2)
      expect(page).to have_no_css('.page-limit-message')
    end
  end

  context 'when dropping a PDF over the page limit onto the dashboard dropzone' do
    let!(:templates) { create_list(:template, 7, account:, author: user, attachment_count: 0) }

    before do
      visit root_path
    end

    after do
      page.driver.wait_for_network_idle
    end

    it 'blocks the upload and shows best-practices guidance' do
      expect(page).to have_css('[data-target="dashboard-dropzone.fileDropzone"]', visible: false)

      page.execute_script(<<~'JS')
        const text = '%PDF-1.4\n' + '1 0 obj << /Type /Page >> endobj\n'.repeat(130)
        const file = new File([text], 'oversize.pdf', { type: 'application/pdf' })
        const transfer = new DataTransfer()
        transfer.items.add(file)
        const zone = document.querySelector('[data-target="dashboard-dropzone.fileDropzone"]')
        zone.dispatchEvent(new DragEvent('drop', { bubbles: true, cancelable: true, dataTransfer: transfer }))
      JS

      expect(page).to have_css('.page-limit-message[role="status"][aria-live="polite"]', text: /split/i)
      expect(page).to have_css('.page-limit-message', text: '120')
      expect(account.templates.count).to eq(templates.count)
    end
  end
end
