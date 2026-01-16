# app/jobs/notification_job.rb
class NotificationJob < ApplicationJob
  queue_as :default

  def perform(user_id, message)
    # 実際の通知処理
    user = User.find(user_id)
    Rails.logger.info("Sending notification to #{user.email}: #{message}")
    
    # 例: メール送信やプッシュ通知など
    # NotificationMailer.send_notification(user, message).deliver_now
  end
end
