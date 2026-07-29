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

  def base_area(overrides = {})
    {
      'x' => 0.1,
      'y' => 0.1,
      'w' => 0.05,
      'h' => 0.05,
      'attachment_uuid' => attachment_uuid,
      'page' => 0
    }.merge(overrides)
  end

  # Point the submitter's submission at fields so fill_submitter_fields reaches
  # the page lookup and drawing branches under test.
  def assign_fields(fields, values = {})
    submitter.submission.update!(template_fields: fields)
    submitter.update!(values: values)
  end

  def fill
    described_class.send(
      :fill_submitter_fields, submitter, account, pdfs_index,
      with_signature_id: false, is_flatten: false, with_headings: false
    )
  end

  def image_xobject_count
    page = pdfs_index[attachment_uuid].pages[0]
    xobjects = page.resources[:XObject]
    return 0 if xobjects.nil?

    count = 0
    # HexaPDF::Dictionary supports each but not each_value
    xobjects.each { |_name, obj| count += 1 if obj[:Subtype] == :Image } # rubocop:disable Style/HashEachMethods
    count
  end

  def page_content_has_text?
    page = pdfs_index[attachment_uuid].pages[0]
    content = page.contents
    content = content.data if content.respond_to?(:data)
    content.to_s.match?(/Tj|TJ/)
  end

  before { allow(Rails.logger).to receive(:warn) }

  describe '.fill_submitter_fields with a missing area page' do
    def assign_field_area(area)
      assign_fields(
        [{ 'uuid' => SecureRandom.uuid, 'submitter_uuid' => submitter.uuid,
           'type' => 'text', 'areas' => [area] }]
      )
    end

    context 'when the area omits the page key' do
      before { assign_field_area('attachment_uuid' => attachment_uuid) }

      it 'skips the area instead of raising (regression: HexaPDF pages[nil])' do
        expect { fill }.not_to raise_error
      end

      it 'logs that the area was skipped' do
        fill
        expect(Rails.logger).to have_received(:warn).with(/Skipping field area with no page/)
      end
    end

    context 'when the area page is explicitly nil' do
      before { assign_field_area('attachment_uuid' => attachment_uuid, 'page' => nil) }

      it 'skips the area instead of raising' do
        expect { fill }.not_to raise_error
      end

      it 'logs that the area was skipped' do
        fill
        expect(Rails.logger).to have_received(:warn).with(/Skipping field area with no page/)
      end
    end

    context 'when the area page is out of range' do
      before { assign_field_area('attachment_uuid' => attachment_uuid, 'page' => 5) }

      it 'does not raise (existing next-if-page-nil handling still applies)' do
        expect { fill }.not_to raise_error
      end

      it 'does not log a skipped-no-page warning (the guard only catches nil)' do
        fill
        expect(Rails.logger).not_to have_received(:warn).with(/Skipping field area with no page/)
      end
    end
  end

  describe '.fill_submitter_fields selection rendering' do
    let(:field_uuid) { SecureRandom.uuid }

    context 'when the field is a checkbox' do
      def assign_checkbox(value)
        assign_fields(
          [{ 'uuid' => field_uuid, 'submitter_uuid' => submitter.uuid,
             'type' => 'checkbox', 'areas' => [base_area] }],
          { field_uuid => value }
        )
      end

      it 'draws a check when value is boolean true' do
        assign_checkbox(true)
        fill
        expect(image_xobject_count).to eq(1)
      end

      it 'draws a check when value is the string "true" (prefill/API truthiness)' do
        assign_checkbox('true')
        fill
        expect(image_xobject_count).to eq(1)
      end

      it 'draws a check for other truthy string values' do
        %w[1 yes].each do |value|
          doc = HexaPDF::Document.new
          doc.pages.add
          pdfs_index[attachment_uuid] = doc

          assign_checkbox(value)
          fill
          expect(image_xobject_count).to eq(1), "expected check for #{value.inspect}"
        end
      end

      it 'does not draw a check when value is false, "false", or nil' do
        [false, 'false', nil].each do |value|
          doc = HexaPDF::Document.new
          doc.pages.add
          pdfs_index[attachment_uuid] = doc

          assign_checkbox(value)
          fill
          expect(image_xobject_count).to eq(0), "expected no check for #{value.inspect}"
        end
      end
    end

    context 'when the field is a radio with option areas' do
      it 'draws a check only on the matching option area' do
        yes_uuid = SecureRandom.uuid
        no_uuid = SecureRandom.uuid
        options = [
          { 'uuid' => yes_uuid, 'value' => 'Yes' },
          { 'uuid' => no_uuid, 'value' => 'No' }
        ]

        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'radio',
            'options' => options,
            'areas' => [
              base_area('option_uuid' => yes_uuid, 'x' => 0.1),
              base_area('option_uuid' => no_uuid, 'x' => 0.3)
            ]
          }],
          { field_uuid => 'Yes' }
        )

        fill
        expect(image_xobject_count).to eq(1)

        # Selected Yes, but only the No area is on the page — must not draw a check.
        doc = HexaPDF::Document.new
        doc.pages.add
        pdfs_index[attachment_uuid] = doc

        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'radio',
            'options' => options,
            'areas' => [base_area('option_uuid' => no_uuid, 'x' => 0.3)]
          }],
          { field_uuid => 'Yes' }
        )

        fill
        expect(image_xobject_count).to eq(0)
      end
    end

    context 'when the field is multiple with option areas' do
      it 'draws a check on each selected option area' do
        opt_a = SecureRandom.uuid
        opt_b = SecureRandom.uuid
        opt_c = SecureRandom.uuid

        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'multiple',
            'options' => [
              { 'uuid' => opt_a, 'value' => 'A' },
              { 'uuid' => opt_b, 'value' => 'B' },
              { 'uuid' => opt_c, 'value' => 'C' }
            ],
            'areas' => [
              base_area('option_uuid' => opt_a, 'x' => 0.1),
              base_area('option_uuid' => opt_b, 'x' => 0.2),
              base_area('option_uuid' => opt_c, 'x' => 0.3)
            ]
          }],
          { field_uuid => %w[A B] }
        )

        fill
        expect(image_xobject_count).to eq(2)
      end
    end

    context 'when a radio option area has a stale option_uuid' do
      let(:stale_option_uuid) { SecureRandom.uuid }

      before do
        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'radio',
            'options' => [{ 'uuid' => SecureRandom.uuid, 'value' => 'Yes' }],
            'areas' => [base_area('option_uuid' => stale_option_uuid)]
          }],
          { field_uuid => 'Yes' }
        )
      end

      it 'skips the area instead of raising' do
        expect { fill }.not_to raise_error
        expect(image_xobject_count).to eq(0)
      end

      it 'logs that the option area was skipped' do
        fill
        expect(Rails.logger).to have_received(:warn).with(
          /Skipping option area with unknown option_uuid.*option_uuid=#{stale_option_uuid}/
        )
      end
    end

    context 'when radio/multiple has a single area without option_uuid' do
      it 'draws selected radio value as text without raising' do
        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'radio',
            'options' => [
              { 'uuid' => SecureRandom.uuid, 'value' => 'Yes' },
              { 'uuid' => SecureRandom.uuid, 'value' => 'No' }
            ],
            'areas' => [base_area('w' => 0.3, 'h' => 0.04)]
          }],
          { field_uuid => 'Yes' }
        )

        expect { fill }.not_to raise_error
        expect(image_xobject_count).to eq(0)
        expect(page_content_has_text?).to be true
      end

      it 'draws selected multiple values as joined text without raising' do
        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'multiple',
            'options' => [
              { 'uuid' => SecureRandom.uuid, 'value' => 'A' },
              { 'uuid' => SecureRandom.uuid, 'value' => 'B' }
            ],
            'areas' => [base_area('w' => 0.4, 'h' => 0.04)]
          }],
          { field_uuid => %w[A B] }
        )

        expect { fill }.not_to raise_error
        expect(image_xobject_count).to eq(0)
        expect(page_content_has_text?).to be true
      end
    end

    context 'when the field is text (regression)' do
      it 'still renders typed text' do
        assign_fields(
          [{
            'uuid' => field_uuid,
            'submitter_uuid' => submitter.uuid,
            'type' => 'text',
            'areas' => [base_area('w' => 0.4, 'h' => 0.04)]
          }],
          { field_uuid => 'Hello world' }
        )

        expect { fill }.not_to raise_error
        expect(page_content_has_text?).to be true
      end
    end
  end
end
