class UserAppDeployJob < ApplicationJob
  queue_as :k8s_operations
  
  retry_on K8s::BaseService::K8sError, wait: 30.seconds, attempts: 3

  def perform(user_id)
    user = User.find(user_id)
    service = K8s::UserAppService.new(user)
    
    service.deploy_user_app
    
    Rails.logger.info "Successfully deployed app for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to deploy app for user #{user_id}: #{e.message}"
    raise
  end
end
