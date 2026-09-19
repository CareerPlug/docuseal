# frozen_string_literal: true

class PageLimitEventsController < ApplicationController
  include IframeAuthentication

  skip_before_action :verify_authenticity_token, only: [:create]
  skip_before_action :authenticate_via_token!

  before_action :authenticate_from_referer

  skip_authorization_check

  BUCKETS = %w[121-150 151-200 201+].freeze
  SURFACES = %w[builder dashboard].freeze

  def create
    return head :unauthorized if current_user.blank?

    page_count = Integer(params[:page_count], exception: false)
    file_size = params[:file_size].present? ? Integer(params[:file_size], exception: false) : nil

    unless valid_event_params?(page_count, file_size)
      return render json: { error: 'Invalid parameters' }, status: :unprocessable_entity
    end

    Rails.logger.info({
      event: 'page_limit_blocked',
      page_count:,
      bucket: params[:bucket],
      surface: params[:surface],
      file_size:,
      account_id: current_account&.id,
      user_id: current_user&.id
    }.to_json)

    head :no_content
  end

  private

  def valid_event_params?(page_count, file_size)
    return false if page_count.blank? || page_count <= 0
    return false unless params[:bucket].in?(BUCKETS) && params[:surface].in?(SURFACES)
    return true if params[:file_size].blank?

    file_size.present? && !file_size.negative?
  end
end
