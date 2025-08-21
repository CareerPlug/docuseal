# frozen_string_literal: true

class ApplicationController < ActionController::Base
  BROWSER_LOCALE_REGEXP = /\A\w{2}(?:-\w{2})?/

  include ActiveStorage::SetCurrent
  include Pagy::Backend

  check_authorization unless: :devise_controller?

  around_action :with_locale
  # before_action :sign_in_for_demo, if: -> { Docuseal.demo? }
  before_action :maybe_authenticate_via_token
  before_action :authenticate_via_token!, unless: :devise_controller?

  helper_method :button_title,
                :current_account,
                :form_link_host,
                :svg_icon

  impersonates :user, with: ->(uuid) { User.find_by(uuid:) }

  rescue_from Pagy::OverflowError do
    redirect_to request.path
  end

  rescue_from RateLimit::LimitApproached do |e|
    Rollbar.error(e) if defined?(Rollbar)

    redirect_to request.referer, alert: 'Too many requests', status: :too_many_requests
  end

  if Rails.env.production? || Rails.env.test?
    rescue_from CanCan::AccessDenied do |e|
      Rollbar.warning(e) if defined?(Rollbar)

      redirect_to root_path, alert: e.message
    end
  end

  def default_url_options
    if request.domain == 'docuseal.com'
      return { host: 'docuseal.com', protocol: ENV['FORCE_SSL'].present? ? 'https' : 'http' }
    end

    Docuseal.default_url_options
  end

  def impersonate_user(user)
    raise ArgumentError unless user
    raise Pretender::Error unless true_user

    @impersonated_user = user

    request.session[:impersonated_user_id] = user.uuid
  end

  def pagy_auto(collection, **keyword_args)
    if current_ability.can?(:manage, :countless)
      pagy_countless(collection, **keyword_args)
    else
      pagy(collection, **keyword_args)
    end
  end

  private

  def with_locale(&)
    return yield unless current_account

    locale   = params[:lang].presence if Rails.env.development?
    locale ||= current_account.locale

    I18n.with_locale(locale, &)
  end

  def with_browser_locale(&)
    return yield if I18n.locale != :'en-US' && I18n.locale != :en

    locale   = params[:lang].presence
    locale ||= request.env['HTTP_ACCEPT_LANGUAGE'].to_s[BROWSER_LOCALE_REGEXP].to_s

    locale =
      if locale.starts_with?('en-') && locale != 'en-US'
        'en-GB'
      else
        locale.split('-').first.presence || 'en-GB'
      end

    locale = 'en-GB' unless I18n.locale_available?(locale)

    I18n.with_locale(locale, &)
  end

  def sign_in_for_demo
    sign_in(User.active.order('random()').take) unless signed_in?
  end

  def current_account
    current_user&.account
  end

  def maybe_authenticate_via_token
    return if signed_in?

    # Check for token in params, session, or X-Auth-Token header
    token = params[:auth_token] || session[:auth_token] || request.headers['X-Auth-Token']
    return unless token.present?

    # Try to find user by token and sign them in
    sha256 = Digest::SHA256.hexdigest(token)
    user = User.joins(:access_token).active.find_by(access_token: { sha256: sha256 })

    if user
      sign_in(user)
      # Store the token in session for future requests
      session[:auth_token] = token
    end
  end

  # Enhanced authentication that tries token auth and fails with error if no user found
  # Use this when you need to enforce authentication with better token handling
  def authenticate_via_token!
    return if signed_in?

    token = params[:auth_token] || session[:auth_token] || request.headers['X-Auth-Token']

    if token.present?
      sha256 = Digest::SHA256.hexdigest(token)
      user = User.joins(:access_token).active.find_by(access_token: { sha256: sha256 })

      if user
        sign_in(user)
        session[:auth_token] = token
        return
      end
    end

    render json: { error: 'Authentication required. Please provide a valid auth_token.' }, status: :unauthorized
  end

  def button_title(title: I18n.t('submit'), disabled_with: I18n.t('submitting'), title_class: '', icon: nil,
                   icon_disabled: nil)
    render_to_string(partial: 'shared/button_title',
                     locals: { title:, disabled_with:, title_class:, icon:, icon_disabled: })
  end

  def svg_icon(icon_name, class: '')
    render_to_string(partial: "icons/#{icon_name}", locals: { class: })
  end

  def form_link_host
    Docuseal.default_url_options[:host]
  end

  def maybe_redirect_com
    return if request.domain != 'docuseal.co'

    redirect_to request.url.gsub('.co/', '.com/'), allow_other_host: true, status: :moved_permanently
  end
end
