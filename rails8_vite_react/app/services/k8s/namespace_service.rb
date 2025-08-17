class K8s::NamespaceService < K8s::BaseService
  def create(namespace)
    handle_k8s_error do
      ns = Kubeclient::Resource.new(
        metadata: {
          name: namespace,
          labels: {
            'managed-by' => 'rails-k8s-controller',
            'user-namespace' => 'true'
          }
        }
      )
      k8s_client.create_namespace(ns)
      Rails.logger.info "Created namespace: #{namespace}"
    end
  end

  def delete(namespace)
    handle_k8s_error do
      k8s_client.delete_namespace(namespace)
      Rails.logger.info "Deleted namespace: #{namespace}"
    end
  end

  def exists?(namespace)
    handle_k8s_error do
      k8s_client.get_namespace(namespace)
      true
    end
  rescue K8sError
    false
  end

  def list_user_namespaces(user_id)
    handle_k8s_error do
      namespaces = k8s_client.get_namespaces(
        label_selector: 'user-namespace=true'
      )
      
      namespaces.select { |ns| ns.metadata.name.start_with?("user-#{user_id}-") }
                .map { |ns| ns.metadata.name }
    end
  end

  def get(namespace)
    handle_k8s_error do
      k8s_client.get_namespace(namespace)
    end
  end
end
