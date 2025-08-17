class SessionTimeoutMonitorJob < ApplicationJob
  queue_as :default

  def perform
    timeout_minutes = Rails.application.config.session_timeout_minutes || 30
    expired_users = User.joins(:user_sessions)
                       .where(app_status: 'running')
                       .where('user_sessions.updated_at < ?', timeout_minutes.minutes.ago)
                       .distinct

    expired_users.find_each do |user|
      UserAppStopJob.perform_later(user.id)
    end

    Rails.logger.info "Scheduled stop jobs for #{expired_users.count} expired user sessions"
  end
end
