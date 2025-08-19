# app/services/kubernetes/ingress_service.rb
module Kubernetes
  class IngressService < BaseService
    class << self
      def list_ingresses(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        networking_v1_client.resource('ingresses', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Ingress', 'list')
      end
      
      def get_ingress(name, namespace: 'default')
        networking_v1_client.resource('ingresses', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Ingress', name)
      end
      
      def create_ingress(spec, namespace: 'default')
        ingress_manifest = build_ingress_manifest(spec, namespace)
        networking_v1_client.resource('ingresses', namespace: validate_namespace(namespace))
                          .create_resource(ingress_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Ingress', spec[:name])
      end
      
      def update_ingress(name, spec, namespace: 'default')
        ingress = get_ingress(name, namespace)
        return nil unless ingress
        
        # Update ingress rules
        ingress.spec.rules = spec[:rules] if spec[:rules]
        ingress.spec.tls = spec[:tls] if spec[:tls]
        ingress.spec.ingressClassName = spec[:ingress_class] if spec[:ingress_class]
        
        networking_v1_client.resource('ingresses', namespace: validate_namespace(namespace))
                          .update_resource(ingress)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Ingress', name)
      end
      
      def delete_ingress(name, namespace: 'default')
        networking_v1_client.resource('ingresses', namespace: validate_namespace(namespace))
                          .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Ingress', name)
      end
      
      def get_ingress_status(name, namespace: 'default')
        ingress = get_ingress(name, namespace)
        return nil unless ingress
        
        {
          ingress_class: ingress.spec&.ingressClassName,
          rules: ingress.spec&.rules,
          tls: ingress.spec&.tls,
          load_balancer: ingress.status&.loadBalancer,
          conditions: ingress.status&.conditions
        }
      end
      
      def wait_for_ingress_ready(name, namespace: 'default', timeout: 300)
        start_time = Time.current
        
        loop do
          ingress = get_ingress(name, namespace)
          return false unless ingress
          
          # Check if ingress has load balancer status
          if ingress.status&.loadBalancer&.ingress&.any?
            return true
          end
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for ingress #{name} to be ready"
            return false
          end
          
          sleep 5
        end
      end
      
      def create_simple_ingress(name, host, service_name, service_port, namespace: 'default', path: '/', path_type: 'Prefix')
        spec = {
          name: name,
          ingress_class: 'nginx', # Default to nginx, can be customized
          rules: [
            {
              host: host,
              http: {
                paths: [
                  {
                    path: path,
                    pathType: path_type,
                    backend: {
                      service: {
                        name: service_name,
                        port: {
                          number: service_port
                        }
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
        
        create_ingress(spec, namespace)
      end
      
      def create_tls_ingress(name, host, service_name, service_port, tls_secret_name, namespace: 'default')
        spec = {
          name: name,
          ingress_class: 'nginx',
          rules: [
            {
              host: host,
              http: {
                paths: [
                  {
                    path: '/',
                    pathType: 'Prefix',
                    backend: {
                      service: {
                        name: service_name,
                        port: {
                          number: service_port
                        }
                      }
                    }
                  }
                ]
              }
            }
          ],
          tls: [
            {
              hosts: [host],
              secretName: tls_secret_name
            }
          ]
        }
        
        create_ingress(spec, namespace)
      end
      
      def add_ingress_rule(name, host, paths, namespace: 'default')
        ingress = get_ingress(name, namespace)
        return nil unless ingress
        
        ingress.spec.rules ||= []
        new_rule = {
          host: host,
          http: {
            paths: paths
          }
        }
        
        # Check if rule for this host already exists
        existing_rule_index = ingress.spec.rules.find_index { |rule| rule.host == host }
        if existing_rule_index
          # Merge paths with existing rule
          ingress.spec.rules[existing_rule_index][:http][:paths] += paths
        else
          # Add new rule
          ingress.spec.rules << new_rule
        end
        
        networking_v1_client.resource('ingresses', namespace: validate_namespace(namespace))
                          .update_resource(ingress)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Ingress rule addition', name)
      end
      
      def get_ingress_endpoints(name, namespace: 'default')
        ingress = get_ingress(name, namespace)
        return [] unless ingress&.status&.loadBalancer&.ingress
        
        endpoints = []
        ingress.status.loadBalancer.ingress.each do |lb_ingress|
          if lb_ingress.ip
            endpoints << { type: 'ip', address: lb_ingress.ip }
          elsif lb_ingress.hostname
            endpoints << { type: 'hostname', address: lb_ingress.hostname }
          end
        end
        
        endpoints
      end
      
      private
      
      def build_ingress_manifest(spec, namespace)
        {
          apiVersion: 'networking.k8s.io/v1',
          kind: 'Ingress',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            ingressClassName: spec[:ingress_class],
            rules: spec[:rules] || [],
            tls: spec[:tls],
            defaultBackend: spec[:default_backend]
          }.compact
        }
      end
    end
  end
end