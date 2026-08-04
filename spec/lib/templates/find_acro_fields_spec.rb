# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Templates::FindAcroFields do
  # Letter media box; field Rect chosen so expected fractions are simple.
  let(:page_w) { 612.0 }
  let(:page_h) { 792.0 }
  let(:field_rect) { [100.0, 100.0, 300.0, 130.0] } # x0, y0, x1, y1 (PDF bottom-left origin)
  let(:attachment) { instance_double(ActiveStorage::Attachment, uuid: SecureRandom.uuid) }

  def build_pdf(rotate: nil, media_box: nil, crop_box: nil, rect: nil)
    doc = HexaPDF::Document.new
    page = doc.pages.add(media_box || [0, 0, page_w, page_h])
    page[:CropBox] = crop_box if crop_box
    page[:Rotate] = rotate if rotate && rotate != 0

    form = doc.acro_form(create: true)
    form.create_text_field('name').create_widget(page, Rect: (rect || field_rect).dup)

    doc
  end

  def extract_area(rotate: nil, media_box: nil, crop_box: nil, rect: nil)
    pdf = build_pdf(rotate:, media_box:, crop_box:, rect:)
    fields = described_class.call(pdf, attachment, '')
    expect(fields).not_to be_empty
    fields.first[:areas].first
  end

  def expect_area(area, expected_x:, expected_y:, expected_w:, expected_h:)
    expect(area[:x]).to be_within(1e-6).of(expected_x)
    expect(area[:y]).to be_within(1e-6).of(expected_y)
    expect(area[:w]).to be_within(1e-6).of(expected_w)
    expect(area[:h]).to be_within(1e-6).of(expected_h)
    expect(area[:page]).to eq(0)
    expect(area[:attachment_uuid]).to eq(attachment.uuid)
  end

  describe '.call with page rotation' do
    it 'preserves media-normalized coords when /Rotate is absent' do
      area = extract_area(rotate: nil)

      expect_area(
        area,
        expected_x: 100 / page_w,
        expected_y: (page_h - 130) / page_h,
        expected_w: 200 / page_w,
        expected_h: 30 / page_h
      )
    end

    it 'preserves media-normalized coords when /Rotate is 0' do
      area = extract_area(rotate: 0)

      expect_area(
        area,
        expected_x: 100 / page_w,
        expected_y: (page_h - 130) / page_h,
        expected_w: 200 / page_w,
        expected_h: 30 / page_h
      )
    end

    it 'maps fields into visual space for /Rotate 90' do
      # Visual rect: [100, 312, 130, 512], visual dims 792×612
      area = extract_area(rotate: 90)

      expect_area(
        area,
        expected_x: 100 / page_h,
        expected_y: (page_w - 512) / page_w,
        expected_w: 30 / page_h,
        expected_h: 200 / page_w
      )
    end

    it 'maps fields into visual space for /Rotate 180' do
      # Visual rect: [312, 662, 512, 692], visual dims 612×792
      area = extract_area(rotate: 180)

      expect_area(
        area,
        expected_x: 312 / page_w,
        expected_y: (page_h - 692) / page_h,
        expected_w: 200 / page_w,
        expected_h: 30 / page_h
      )
    end

    it 'maps fields into visual space for /Rotate 270' do
      # Visual rect: [662, 100, 692, 300], visual dims 792×612
      area = extract_area(rotate: 270)

      expect_area(
        area,
        expected_x: 662 / page_h,
        expected_y: (page_w - 300) / page_w,
        expected_w: 30 / page_h,
        expected_h: 200 / page_w
      )
    end

    it 'maps fields for /Rotate 90 when MediaBox is not 0-origin' do
      # Offsets [10, 20]; absolute Rect chosen so correct_coordinates yields the
      # same 0-origin rect as the base cases ([100, 100, 300, 130]). Extents-based
      # rotation only matches HexaPDF flatten after that normalization.
      media_box = [10.0, 20.0, 10.0 + page_w, 20.0 + page_h]
      rect = [110.0, 120.0, 310.0, 150.0]
      area = extract_area(rotate: 90, media_box:, rect:)

      expect_area(
        area,
        expected_x: 100 / page_h,
        expected_y: (page_w - 512) / page_w,
        expected_w: 30 / page_h,
        expected_h: 200 / page_w
      )
    end

    it 'uses CropBox extents for /Rotate 90 when CropBox differs from MediaBox' do
      # media_box up top is CropBox whenever present. Larger MediaBox must not
      # change width/height or the post-correct_coordinates origin.
      media_box = [0.0, 0.0, 700.0, 900.0]
      crop_box = [10.0, 20.0, 10.0 + page_w, 20.0 + page_h]
      rect = [110.0, 120.0, 310.0, 150.0]
      area = extract_area(rotate: 90, media_box:, crop_box:, rect:)

      expect_area(
        area,
        expected_x: 100 / page_h,
        expected_y: (page_w - 512) / page_w,
        expected_w: 30 / page_h,
        expected_h: 200 / page_w
      )
    end
  end
end
