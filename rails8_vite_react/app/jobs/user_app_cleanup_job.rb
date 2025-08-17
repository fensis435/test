class UserAppCleanupJob < ApplicationJob
  queue_as :k8s_operations
  
  def perform(user_id)
    # Find user record or create a temporary one for cleanup
    user = User.find_by(id: user_id) || 
           User.new(id: user_id, k8s_namespace: find_user_namespace(user_id))
    
    service = K8s::UserAppService.new(user)
    service.undeploy_user_app
    
    Rails.logger.info "Successfully cleaned up resources for user #{user_id}"
  rescue => e
    Rails.logger.error "Failed to cleanup resources for user #{user_id}: #{e.message}"
  end

  private

  def find_user_namespace(user_id)
    service = K8s::NamespaceService.new
    namespaces = service.list_user_namespaces(user_id)
    namespaces.first
  end
end
