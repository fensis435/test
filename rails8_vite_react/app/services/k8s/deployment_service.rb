class K8s::DeploymentService < K8s::BaseService
  def scale(deployment_name:, namespace:, replicas:)
    handle_k8s_error do
      deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
      deployment.spec.replicas = replicas
      k8s_apps_client.update_deployment(deployment)
      Rails.logger.info "Scaled deployment #{deployment_name} to #{replicas} replicas in namespace: #{namespace}"
    end
  end

  def restart(deployment_name:, namespace:)
    handle_k8s_error do
      deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
      
      # Add restart annotation to trigger rolling restart
      deployment.spec.template.metadata.annotations ||= {}
      deployment.spec.template.metadata.annotations['kubectl.kubernetes.io/restartedAt'] = Time.current.iso8601
      
      k8s_apps_client.update_deployment(deployment)
      Rails.logger.info "Restarted deployment: #{deployment_name} in namespace: #{namespace}"
    end
  end

  def status(deployment_name:, namespace:)
    handle_k8s_error do
      deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
      {
        'metadata' => {
          'name' => deployment.metadata.name,
          'namespace' => deployment.metadata.namespace
        },
        'status' => {
          'replicas' => deployment.status.replicas,
          'readyReplicas' => deployment.status.readyReplicas,
          'unavailableReplicas' => deployment.status.unavailableReplicas,
          'conditions' => deployment.status.conditions&.map(&:to_h)
        }
      }
    end
  end

  def wait_for_rollout(deployment_name:, namespace:, timeout: 300)
    handle_k8s_error do
      start_time = Time.current
      
      loop do
        deployment = k8s_apps_client.get_deployment(deployment_name, namespace)
        
        desired_replicas = deployment.spec.replicas || 0
        ready_replicas = deployment.status.readyReplicas || 0
        
        break if ready_replicas >= desired_replicas
        
        if Time.current - start_time > timeout
          raise K8sError, "Timeout waiting for deployment #{deployment_name} rollout"
        end
        
        sleep 5
      end
      
      Rails.logger.info "Deployment #{deployment_name} rollout completed in namespace: #{namespace}"
    end
  end

  def get_pods(deployment_name:, namespace:)
    handle_k8s_error do
      pods = k8s_client.get_pods(
        namespace: namespace,
        label_selector: "app=#{deployment_name}"
      )
      
      {
        'items' => pods.map do |pod|
          {
            'metadata' => {
              'name' => pod.metadata.name,
              'namespace' => pod.metadata.namespace
            },
            'status' => {
              'phase' => pod.status.phase,
              'conditions' => pod.status.conditions&.map(&:to_h)
            }
          }
        end
      }
    end
  end

  def exists?(deployment_name:, namespace:)
    handle_k8s_error do
      k8s_apps_client.get_deployment(deployment_name, namespace)
      true
    end
  rescue K8sError
    false
  end
end

