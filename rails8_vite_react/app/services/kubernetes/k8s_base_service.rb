# app/services/kubernetes/base_service.rb
module Kubernetes
  class BaseService
    include ActiveSupport::Configurable
    
    class << self
      def client
        @client ||= K8s::Client.in_cluster_config
      rescue K8s::Error::Config
        # Fallback to kubeconfig for development
        @client ||= K8s::Client.config(
          K8s::Config.load_file(File.expand_path('~/.kube/config'))
        )
      end
      
      def api_client
        client.api
      end
      
      def apps_v1_client
        client.api('apps/v1')
      end
      
      def core_v1_client
        client.api('v1')
      end
      
      def networking_v1_client
        client.api('networking.k8s.io/v1')
      end
      
      def rbac_v1_client
        client.api('rbac.authorization.k8s.io/v1')
      end
      
      def batch_v1_client
        client.api('batch/v1')
      end
      
      def autoscaling_v1_client
        client.api('autoscaling/v1')
      end
    end
    
    protected
    
    def handle_k8s_error(error, resource_type, name = nil)
      case error
      when K8s::Error::NotFound
        Rails.logger.warn "#{resource_type} #{name} not found"
        nil
      when K8s::Error::Conflict
        Rails.logger.error "#{resource_type} #{name} already exists or conflict occurred"
        raise StandardError, "Resource conflict: #{error.message}"
      when K8s::Error::Forbidden
        Rails.logger.error "Access forbidden for #{resource_type} #{name}"
        raise StandardError, "Access forbidden: #{error.message}"
      else
        Rails.logger.error "Kubernetes error for #{resource_type} #{name}: #{error.message}"
        raise StandardError, "Kubernetes operation failed: #{error.message}"
      end
    end
    
    def build_labels(custom_labels = {})
      default_labels = {
        'app.kubernetes.io/managed-by' => 'rails-app',
        'app.kubernetes.io/created-by' => 'kubernetes-service'
      }
      default_labels.merge(custom_labels)
    end
    
    def build_annotations(custom_annotations = {})
      default_annotations = {
        'kubernetes.service/created-at' => Time.current.iso8601
      }
      default_annotations.merge(custom_annotations)
    end
    
    def validate_namespace(namespace)
      return 'default' if namespace.blank?
      namespace
    end
  end
end