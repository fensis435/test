class UserAppStopJob < ApplicationJob
  queue_as :k8s_operations
  
  retry_on K8s::BaseService::K8sError, wait: 10.seconds, attempts: 2

  def perform(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    service.stop_user_app
    
    Rails.logger.info "Successfully stopped app for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to stop app for user #{user_id}: #{e.message}"
    raise
  end
end
