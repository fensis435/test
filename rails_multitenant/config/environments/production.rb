Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = ENV["RAILS_SERVE_STATIC_FILES"].present?

  config.log_level = :info
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(
    ActiveSupport::Logger.new($stdout).tap do |logger|
      logger.formatter = proc do |severity, timestamp, progname, message|
        {
          timestamp: timestamp.iso8601,
          severity: severity,
          progname: progname,
          message: message
        }.to_json + "\n"
      end
    end
  )

  config.active_record.dump_schema_after_migration = false
  config.active_record.query_log_tags_enabled = true
  config.active_record.query_log_tags = [:application, :controller, :action, :job]

  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  config.active_support.report_deprecations = false

  config.action_dispatch.default_headers = {
    "X-Frame-Options" => "DENY",
    "X-XSS-Protection" => "1; mode=block",
    "X-Content-Type-Options" => "nosniff",
    "X-Download-Options" => "noopen",
    "X-Permitted-Cross-Domain-Policies" => "none",
    "Referrer-Policy" => "strict-origin-when-cross-origin"
  }
end
