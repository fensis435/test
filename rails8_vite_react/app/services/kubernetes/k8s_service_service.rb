# app/services/kubernetes/service_service.rb
module Kubernetes
  class ServiceService < BaseService
    class << self
      def list_services(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        core_v1_client.resource('services', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Service', 'list')
      end
      
      def get_service(name, namespace: 'default')
        core_v1_client.resource('services', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Service', name)
      end
      
      def create_service(spec, namespace: 'default')
        service_manifest = build_service_manifest(spec, namespace)
        core_v1_client.resource('services', namespace: validate_namespace(namespace))
                     .create_resource(service_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Service', spec[:name])
      end
      
      def update_service(name, spec, namespace: 'default')
        service = get_service(name, namespace)
        return nil unless service
        
        # Update service spec
        service.spec.ports = spec[:ports] if spec[:ports]
        service.spec.selector = spec[:selector] if spec[:selector]
        service.spec.type = spec[:type] if spec[:type]
        
        core_v1_client.resource('services', namespace: validate_namespace(namespace))
                     .update_resource(service)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Service', name)
      end
      
      def delete_service(name, namespace: 'default')
        core_v1_client.resource('services', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Service', name)
      end
      
      def get_service_endpoints(name, namespace: 'default')
        core_v1_client.resource('endpoints', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Endpoints', name)
      end
      
      def create_headless_service(spec, namespace: 'default')
        spec[:cluster_ip] = 'None'
        create_service(spec, namespace)
      end
      
      def create_load_balancer_service(spec, namespace: 'default')
        spec[:type] = 'LoadBalancer'
        create_service(spec, namespace)
      end
      
      def create_node_port_service(spec, namespace: 'default')
        spec[:type] = 'NodePort'
        create_service(spec, namespace)
      end
      
      def get_service_status(name, namespace: 'default')
        service = get_service(name, namespace)
        return nil unless service
        
        status = {
          cluster_ip: service.spec&.clusterIP,
          external_ips: service.spec&.externalIPs,
          type: service.spec&.type,
          ports: service.spec&.ports,
          selector: service.spec&.selector
        }
        
        # Add LoadBalancer specific status
        if service.spec&.type == 'LoadBalancer'
          status[:load_balancer] = {
            ingress: service.status&.loadBalancer&.ingress
          }
        end
        
        status
      end
      
      def wait_for_load_balancer_ready(name, namespace: 'default', timeout: 300)
        return false unless get_service(name, namespace)&.spec&.type == 'LoadBalancer'
        
        start_time = Time.current
        
        loop do
          service = get_service(name, namespace)
          return false unless service
          
          if service.status&.loadBalancer&.ingress&.any?
            return true
          end
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for LoadBalancer service #{name} to get external IP"
            return false
          end
          
          sleep 5
        end
      end
      
      def get_service_pods(name, namespace: 'default')
        service = get_service(name, namespace)
        return [] unless service&.spec&.selector
        
        label_selector = service.spec.selector.map { |k, v| "#{k}=#{v}" }.join(',')
        PodService.list_pods(namespace: namespace, label_selector: label_selector)
      end
      
      private
      
      def build_service_manifest(spec, namespace)
        {
          apiVersion: 'v1',
          kind: 'Service',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            selector: spec[:selector] || {},
            ports: spec[:ports] || [],
            type: spec[:type] || 'ClusterIP',
            clusterIP: spec[:cluster_ip],
            externalIPs: spec[:external_ips],
            loadBalancerIP: spec[:load_balancer_ip],
            loadBalancerSourceRanges: spec[:load_balancer_source_ranges],
            externalName: spec[:external_name],
            sessionAffinity: spec[:session_affinity] || 'None',
            externalTrafficPolicy: spec[:external_traffic_policy]
          }.compact
        }
      end
    end
  end
end