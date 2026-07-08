# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Submissions::GenerateResultAttachments do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:template) { create(:template, account:, author: user) }
  let(:submission) { create(:submission, template:, created_by_user: user) }
  let(:submitter) { create(:submitter, submission:, uuid: SecureRandom.uuid) }
  let(:attachment_uuid) { SecureRandom.uuid }

  # A single-page in-memory PDF keyed by the area's attachment_uuid, so the
  # `pdf.nil?` guard passes and we reach the `pdf.pages[area['page']]` index.
  let(:pdfs_index) do
    doc = HexaPDF::Document.new
    doc.pages.add
    { attachment_uuid => doc }
  end

  # Point the submitter's submission at a single text field whose one area is
  # `area`, so `fill_submitter_fields` reaches the page lookup for that area.
  def set_field_area(area)
    submitter.submission.update!(
      template_fields: [
        { 'uuid' => SecureRandom.uuid, 'submitter_uuid' => submitter.uuid,
          'type' => 'text', 'areas' => [area] }
      ]
    )
  end

  def fill
    described_class.send(
      :fill_submitter_fields, submitter, account, pdfs_index,
      with_signature_id: false, is_flatten: false, with_headings: false
    )
  end

  before { allow(Rails.logger).to receive(:warn) }

  describe '.fill_submitter_fields with a missing area page' do
    context 'when the area omits the page key' do
      before { set_field_area('attachment_uuid' => attachment_uuid) }

      it 'skips the area instead of raising (regression: HexaPDF pages[nil])' do
        expect { fill }.not_to raise_error
      end

      it 'logs that the area was skipped' do
        fill
        expect(Rails.logger).to have_received(:warn).with(/Skipping field area with no page/)
      end
    end

    context 'when the area page is explicitly nil' do
      before { set_field_area('attachment_uuid' => attachment_uuid, 'page' => nil) }

      it 'skips the area instead of raising' do
        expect { fill }.not_to raise_error
      end

      it 'logs that the area was skipped' do
        fill
        expect(Rails.logger).to have_received(:warn).with(/Skipping field area with no page/)
      end
    end

    context 'when the area page is out of range' do
      before { set_field_area('attachment_uuid' => attachment_uuid, 'page' => 5) }

      it 'does not raise (existing next-if-page-nil handling still applies)' do
        expect { fill }.not_to raise_error
      end

      it 'does not log a skipped-no-page warning (the guard only catches nil)' do
        fill
        expect(Rails.logger).not_to have_received(:warn).with(/Skipping field area with no page/)
      end
    end
  end
end
