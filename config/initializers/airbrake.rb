unless ENV['DOCKER_BUILD']
  Airbrake.configure do |config|
    config.project_key = ENV['AIRBRAKE_KEY']
    config.project_id = ENV['AIRBRAKE_ID']
    config.environment = Rails.env
    config.ignore_environments = %w[development test]
    config.blocklist_keys = Rails.application.config.filter_parameters
    config.root_directory = '/var/cpd/app'
  end
  # Copied wholesale from ATS. Can modify as need be.
  AIRBRAKE_IGNORE = [
    'AbstractController::ActionNotFound',
    'ActionController::InvalidAuthenticityToken',
    'ActionController::RoutingError',
    'ActionController::UnknownAction',
    'ActionController::UnknownFormat',
    'ActionController::UnknownHttpMethod',
    'ActionDispatch::Http::MimeNegotiation::InvalidType',
    'ActiveJobRetryError',
    'ActiveRecord::RecordNotFound',
    'CGI::Session::CookieStore::TamperedWithCookie',
    'DependentResourceJob::ResourceNotYetAvailableError',
    'Sift::WorkflowJobError',
    'Inbound::ReplyHandlerEmailBlockedError'
  ].freeze
  Airbrake.add_filter do |notice|
    notice.ignore! if notice[:errors].any? { |error| AIRBRAKE_IGNORE.include?(error[:type]) }
  end
end
