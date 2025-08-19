# app/services/kubernetes/pod_service.rb
module Kubernetes
  class PodService < BaseService
    class << self
      def list_pods(namespace: 'default', label_selector: nil, field_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        options[:fieldSelector] = field_selector if field_selector.present?
        
        core_v1_client.resource('pods', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod', 'list')
      end
      
      def get_pod(name, namespace: 'default')
        core_v1_client.resource('pods', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod', name)
      end
      
      def create_pod(spec, namespace: 'default')
        pod_manifest = build_pod_manifest(spec, namespace)
        core_v1_client.resource('pods', namespace: validate_namespace(namespace)).create_resource(pod_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod', spec[:name])
      end
      
      def delete_pod(name, namespace: 'default', force: false)
        options = force ? { gracePeriodSeconds: 0 } : {}
        core_v1_client.resource('pods', namespace: validate_namespace(namespace)).delete_resource(name, **options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod', name)
      end
      
      def get_pod_logs(name, namespace: 'default', container: nil, follow: false, tail_lines: nil)
        options = {}
        options[:container] = container if container.present?
        options[:follow] = follow
        options[:tailLines] = tail_lines if tail_lines.present?
        
        core_v1_client.resource('pods', namespace: validate_namespace(namespace))
                     .subresource('log', name, **options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod logs', name)
      end
      
      def get_pod_status(name, namespace: 'default')
        pod = get_pod(name, namespace)
        return nil unless pod
        
        {
          phase: pod.status&.phase,
          conditions: pod.status&.conditions,
          container_statuses: pod.status&.containerStatuses,
          host_ip: pod.status&.hostIP,
          pod_ip: pod.status&.podIP,
          start_time: pod.status&.startTime,
          ready: pod_ready?(pod)
        }
      end
      
      def exec_command(name, command, namespace: 'default', container: nil, stdin: false, tty: false)
        options = {
          command: command,
          stdin: stdin,
          stdout: true,
          stderr: true,
          tty: tty
        }
        options[:container] = container if container.present?
        
        core_v1_client.resource('pods', namespace: validate_namespace(namespace))
                     .subresource('exec', name, **options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod exec', name)
      end
      
      def port_forward(name, local_port, remote_port, namespace: 'default')
        # Note: This is a simplified version. Full implementation would require WebSocket handling
        core_v1_client.resource('pods', namespace: validate_namespace(namespace))
                     .subresource('portforward', name, ports: "#{local_port}:#{remote_port}")
      rescue K8s::Error => e
        handle_k8s_error(e, 'Pod port-forward', name)
      end
      
      def wait_for_pod_ready(name, namespace: 'default', timeout: 300)
        start_time = Time.current
        
        loop do
          pod = get_pod(name, namespace)
          return false unless pod
          return true if pod_ready?(pod)
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for pod #{name} to be ready"
            return false
          end
          
          sleep 2
        end
      end
      
      private
      
      def build_pod_manifest(spec, namespace)
        {
          apiVersion: 'v1',
          kind: 'Pod',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            containers: spec[:containers] || [],
            restartPolicy: spec[:restart_policy] || 'Never',
            nodeSelector: spec[:node_selector],
            tolerations: spec[:tolerations],
            affinity: spec[:affinity],
            volumes: spec[:volumes],
            serviceAccountName: spec[:service_account_name]
          }.compact
        }
      end
      
      def pod_ready?(pod)
        return false unless pod.status&.conditions
        
        ready_condition = pod.status.conditions.find { |c| c.type == 'Ready' }
        ready_condition&.status == 'True'
      end
    end
  end
end