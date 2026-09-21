# frozen_string_literal: true

class PageLimitEventsController < ApplicationController
  include IframeAuthentication

  skip_before_action :verify_authenticity_token, only: [:create]
  skip_before_action :authenticate_via_token!

  before_action :authenticate_from_referer

  skip_authorization_check

  SURFACES = %w[builder dashboard].freeze
  PAGE_LIMIT = 120
  MAX_INTEGER_LENGTH = 10

  def create
    return head :unauthorized if current_user.blank?

    page_count = parse_integer(params[:page_count])
    file_size = params[:file_size].present? ? parse_integer(params[:file_size]) : nil

    unless valid_event_params?(page_count, file_size)
      return render json: { error: 'Invalid parameters' }, status: :unprocessable_entity
    end

    Rails.logger.info({
      event: 'page_limit_blocked',
      page_count:,
      bucket: bucket_for(page_count),
      surface: params[:surface],
      file_size:,
      account_id: current_account&.id,
      user_id: current_user&.id
    }.to_json)

    head :no_content
  end

  private

  def valid_event_params?(page_count, file_size)
    return false if page_count.blank? || page_count <= PAGE_LIMIT
    return false unless params[:surface].in?(SURFACES)
    return true if params[:file_size].blank?

    file_size.present? && !file_size.negative?
  end

  def bucket_for(page_count)
    return '121-150' if page_count <= 150
    return '151-200' if page_count <= 200

    '201+'
  end

  def parse_integer(value)
    return nil unless value.to_s.match?(/\A\d{1,#{MAX_INTEGER_LENGTH}}\z/o)

    Integer(value, exception: false)
  end
end
