# app/services/kubernetes/deployment_service.rb
module Kubernetes
  class DeploymentService < BaseService
    class << self
      def list_deployments(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment', 'list')
      end
      
      def get_deployment(name, namespace: 'default')
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment', name)
      end
      
      def create_deployment(spec, namespace: 'default')
        deployment_manifest = build_deployment_manifest(spec, namespace)
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace))
                     .create_resource(deployment_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment', spec[:name])
      end
      
      def update_deployment(name, spec, namespace: 'default')
        deployment = get_deployment(name, namespace)
        return nil unless deployment
        
        # Update the deployment spec
        deployment.spec.template.spec.containers = spec[:containers] if spec[:containers]
        deployment.spec.replicas = spec[:replicas] if spec[:replicas]
        
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace))
                     .update_resource(deployment)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment', name)
      end
      
      def delete_deployment(name, namespace: 'default')
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment', name)
      end
      
      def scale_deployment(name, replicas, namespace: 'default')
        deployment = get_deployment(name, namespace)
        return nil unless deployment
        
        deployment.spec.replicas = replicas
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace))
                     .update_resource(deployment)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment scale', name)
      end
      
      def restart_deployment(name, namespace: 'default')
        deployment = get_deployment(name, namespace)
        return nil unless deployment
        
        # Add restart annotation to force rolling update
        deployment.spec.template.metadata.annotations ||= {}
        deployment.spec.template.metadata.annotations['kubectl.kubernetes.io/restartedAt'] = Time.current.iso8601
        
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace))
                     .update_resource(deployment)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment restart', name)
      end
      
      def get_deployment_status(name, namespace: 'default')
        deployment = get_deployment(name, namespace)
        return nil unless deployment
        
        {
          replicas: deployment.spec&.replicas,
          available_replicas: deployment.status&.availableReplicas,
          ready_replicas: deployment.status&.readyReplicas,
          updated_replicas: deployment.status&.updatedReplicas,
          unavailable_replicas: deployment.status&.unavailableReplicas,
          conditions: deployment.status&.conditions,
          ready: deployment_ready?(deployment)
        }
      end
      
      def wait_for_deployment_ready(name, namespace: 'default', timeout: 600)
        start_time = Time.current
        
        loop do
          deployment = get_deployment(name, namespace)
          return false unless deployment
          return true if deployment_ready?(deployment)
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for deployment #{name} to be ready"
            return false
          end
          
          sleep 5
        end
      end
      
      def get_deployment_pods(name, namespace: 'default')
        deployment = get_deployment(name, namespace)
        return [] unless deployment
        
        label_selector = deployment.spec&.selector&.matchLabels&.map { |k, v| "#{k}=#{v}" }&.join(',')
        return [] unless label_selector
        
        PodService.list_pods(namespace: namespace, label_selector: label_selector)
      end
      
      def rollback_deployment(name, revision: nil, namespace: 'default')
        # Get deployment rollout history first if no specific revision
        deployment = get_deployment(name, namespace)
        return nil unless deployment
        
        # Create rollback patch
        rollback_patch = {
          spec: {
            rollbackTo: {
              revision: revision
            }
          }
        }
        
        apps_v1_client.resource('deployments', namespace: validate_namespace(namespace))
                     .patch_resource(name, rollback_patch, strategic_merge: true)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Deployment rollback', name)
      end
      
      private
      
      def build_deployment_manifest(spec, namespace)
        {
          apiVersion: 'apps/v1',
          kind: 'Deployment',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            replicas: spec[:replicas] || 1,
            selector: {
              matchLabels: spec[:selector_labels] || { app: spec[:name] }
            },
            template: {
              metadata: {
                labels: build_labels((spec[:selector_labels] || { app: spec[:name] }).merge(spec[:pod_labels] || {})),
                annotations: spec[:pod_annotations] || {}
              },
              spec: {
                containers: spec[:containers] || [],
                volumes: spec[:volumes],
                serviceAccountName: spec[:service_account_name],
                nodeSelector: spec[:node_selector],
                tolerations: spec[:tolerations],
                affinity: spec[:affinity],
                imagePullSecrets: spec[:image_pull_secrets]
              }.compact
            },
            strategy: spec[:strategy],
            revisionHistoryLimit: spec[:revision_history_limit] || 10,
            progressDeadlineSeconds: spec[:progress_deadline_seconds] || 600
          }.compact
        }
      end
      
      def deployment_ready?(deployment)
        return false unless deployment.status
        
        # Check if all replicas are available
        desired_replicas = deployment.spec&.replicas || 0
        available_replicas = deployment.status&.availableReplicas || 0
        
        desired_replicas == available_replicas && available_replicas > 0
      end
    end
  end
end