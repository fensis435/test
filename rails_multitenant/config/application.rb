require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module RailsMultitenant
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    config.autoload_lib(ignore: %w[assets tasks])

    config.middleware.use ActionDispatch::RequestId
    config.middleware.insert_before 0, Rack::Attack

    config.i18n.default_locale = :ja
    config.i18n.available_locales = %i[ja en]
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.yml")]

    config.active_job.queue_adapter = :sidekiq

    config.x.tenant.isolation_strategy = ENV.fetch("TENANT_ISOLATION_STRATEGY", "schema")
    config.x.tenant.default_schema = "public"
    config.x.tenant.max_pool_size = ENV.fetch("TENANT_MAX_POOL_SIZE", 5).to_i

    config.x.auth.cognito_user_pool_id = ENV["COGNITO_USER_POOL_ID"]
    config.x.auth.cognito_region = ENV.fetch("AWS_REGION", "ap-northeast-1")
    config.x.auth.jwt_algorithm = "RS256"
    config.x.auth.token_cache_ttl = 300

    config.x.database.platform = ENV.fetch("PLATFORM", "aws")
    config.x.database.onprem_namespace = ENV.fetch("K8S_NAMESPACE", "default")

    config.exceptions_app = routes
  end
end
