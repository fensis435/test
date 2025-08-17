class K8s::StatefulSetService < K8s::BaseService
  def scale(stateful_set_name:, namespace:, replicas:)
    handle_k8s_error do
      stateful_set = k8s_apps_client.get_stateful_set(stateful_set_name, namespace)
      stateful_set.spec.replicas = replicas
      k8s_apps_client.update_stateful_set(stateful_set)
      Rails.logger.info "Scaled StatefulSet #{stateful_set_name} to #{replicas} replicas in namespace: #{namespace}"
    end
  end

  def restart(stateful_set_name:, namespace:)
    handle_k8s_error do
      stateful_set = k8s_apps_client.get_stateful_set(stateful_set_name, namespace)
      
      # Add restart annotation to trigger rolling restart
      stateful_set.spec.template.metadata.annotations ||= {}
      stateful_set.spec.template.metadata.annotations['kubectl.kubernetes.io/restartedAt'] = Time.current.iso8601
      
      k8s_apps_client.update_stateful_set(stateful_set)
      Rails.logger.info "Restarted StatefulSet: #{stateful_set_name} in namespace: #{namespace}"
    end
  end

  def status(stateful_set_name:, namespace:)
    handle_k8s_error do
      stateful_set = k8s_apps_client.get_stateful_set(stateful_set_name, namespace)
      {
        'metadata' => {
          'name' => stateful_set.metadata.name,
          'namespace' => stateful_set.metadata.namespace
        },
        'status' => {
          'replicas' => stateful_set.status.replicas,
          'readyReplicas' => stateful_set.status.readyReplicas,
          'currentReplicas' => stateful_set.status.currentReplicas,
          'updatedReplicas' => stateful_set.status.updatedReplicas,
          'currentRevision' => stateful_set.status.currentRevision,
          'updateRevision' => stateful_set.status.updateRevision,
          'conditions' => stateful_set.status.conditions&.map(&:to_h)
        }
      }
    end
  end

  def wait_for_rollout(stateful_set_name:, namespace:, timeout: 600)
    handle_k8s_error do
      start_time = Time.current
      
      loop do
        stateful_set = k8s_apps_client.get_stateful_set(stateful_set_name, namespace)
        
        desired_replicas = stateful_set.spec.replicas || 0
        ready_replicas = stateful_set.status.readyReplicas || 0
        current_replicas = stateful_set.status.currentReplicas || 0
        updated_replicas = stateful_set.status.updatedReplicas || 0
        
        # StatefulSet is ready when all replicas are ready and updated
        break if ready_replicas >= desired_replicas && 
                 current_replicas >= desired_replicas && 
                 updated_replicas >= desired_replicas
        
        if Time.current - start_time > timeout
          raise K8sError, "Timeout waiting for StatefulSet #{stateful_set_name} rollout"
        end
        
        sleep 10 # StatefulSets take longer to update
      end
      
      Rails.logger.info "StatefulSet #{stateful_set_name} rollout completed in namespace: #{namespace}"
    end
  end

  def get_pods(stateful_set_name:, namespace:)
    handle_k8s_error do
      pods = k8s_client.get_pods(
        namespace: namespace,
        label_selector: "app=#{stateful_set_name}"
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

  def delete_pod(pod_name:, namespace:)
    handle_k8s_error do
      k8s_client.delete_pod(pod_name, namespace)
      Rails.logger.info "Deleted StatefulSet pod: #{pod_name} in namespace: #{namespace}"
    end
  end

  def get_persistent_volume_claims(stateful_set_name:, namespace:)
    handle_k8s_error do
      pvcs = k8s_client.get_persistent_volume_claims(
        namespace: namespace,
        label_selector: "app=#{stateful_set_name}"
      )
      
      {
        'items' => pvcs.map do |pvc|
          {
            'metadata' => {
              'name' => pvc.metadata.name,
              'namespace' => pvc.metadata.namespace
            },
            'status' => {
              'phase' => pvc.status.phase,
              'capacity' => pvc.status.capacity
            }
          }
        end
      }
    end
  end

  def exists?(stateful_set_name:, namespace:)
    handle_k8s_error do
      k8s_apps_client.get_stateful_set(stateful_set_name, namespace)
      true
    end
  rescue K8sError
    false
  end
end
