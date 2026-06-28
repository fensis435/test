Sidekiq.configure_server do |config|
  config.redis = {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }

  config.logger = Rails.logger

  config.death_handlers << lambda do |job, exception|
    Rails.logger.error(
      "Job permanently failed",
      job_class: job["class"],
      job_id: job["jid"],
      error: exception.message
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"),
    ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
  }
end
