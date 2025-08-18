require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MuiSample
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.api_only = true

    # config.eager_load_paths += %W(#{config.root}/lib)

    # JWTトークンの有効期限設定
    config.jwt_expiration_hours = 24
    config.jwt_refresh_expiration_days = 7
    
    # 新規登録の許可設定
    config.allow_registration = ENV.fetch('ALLOW_REGISTRATION', 'true') == 'true'

    # Kubernetes configuration
    config.helm_chart_path = ENV['HELM_CHART_PATH'] || './helm-charts/user-app'
    config.helm_chart_name = ENV['HELM_CHART_NAME'] || 'user-app'
    config.helm_values_file = ENV['HELM_VALUES_FILE'] || './helm-charts/user-app/values.yaml'
    config.app_image_tag = ENV['APP_IMAGE_TAG'] || 'latest'
    config.app_base_domain = ENV['APP_BASE_DOMAIN'] || 'app.example.com'

    # Session and lifecycle configuration
    config.session_timeout_minutes = ENV['SESSION_TIMEOUT_MINUTES']&.to_i || 30
    config.auto_deploy_user_apps = ENV['AUTO_DEPLOY_USER_APPS'] == 'true'

    # Job queues
    config.active_job.queue_adapter = :sidekiq
  end
end
