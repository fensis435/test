# app/services/kubernetes/config_service.rb
module Kubernetes
  class ConfigService < BaseService
    class << self
      # ConfigMap operations
      def list_configmaps(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        core_v1_client.resource('configmaps', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ConfigMap', 'list')
      end
      
      def get_configmap(name, namespace: 'default')
        core_v1_client.resource('configmaps', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ConfigMap', name)
      end
      
      def create_configmap(name, data: {}, binary_data: {}, namespace: 'default', labels: {}, annotations: {})
        configmap_manifest = {
          apiVersion: 'v1',
          kind: 'ConfigMap',
          metadata: {
            name: name,
            namespace: validate_namespace(namespace),
            labels: build_labels(labels),
            annotations: build_annotations(annotations)
          },
          data: data,
          binaryData: binary_data
        }.compact
        
        # Remove empty data fields
        configmap_manifest.delete(:data) if data.empty?
        configmap_manifest.delete(:binaryData) if binary_data.empty?
        
        core_v1_client.resource('configmaps', namespace: validate_namespace(namespace))
                     .create_resource(configmap_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ConfigMap', name)
      end
      
      def update_configmap(name, data: {}, binary_data: {}, namespace: 'default')
        configmap = get_configmap(name, namespace)
        return nil unless configmap
        
        configmap.data = data unless data.empty?
        configmap.binaryData = binary_data unless binary_data.empty?
        
        core_v1_client.resource('configmaps', namespace: validate_namespace(namespace))
                     .update_resource(configmap)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ConfigMap', name)
      end
      
      def delete_configmap(name, namespace: 'default')
        core_v1_client.resource('configmaps', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ConfigMap', name)
      end
      
      # Secret operations
      def list_secrets(namespace: 'default', label_selector: nil, type: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        options[:fieldSelector] = "type=#{type}" if type.present?
        
        core_v1_client.resource('secrets', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Secret', 'list')
      end
      
      def get_secret(name, namespace: 'default')
        core_v1_client.resource('secrets', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Secret', name)
      end
      
      def create_secret(name, data: {}, string_data: {}, type: 'Opaque', namespace: 'default', labels: {}, annotations: {})
        secret_manifest = {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: name,
            namespace: validate_namespace(namespace),
            labels: build_labels(labels),
            annotations: build_annotations(annotations)
          },
          type: type,
          data: data,
          stringData: string_data
        }.compact
        
        # Remove empty data fields
        secret_manifest.delete(:data) if data.empty?
        secret_manifest.delete(:stringData) if string_data.empty?
        
        core_v1_client.resource('secrets', namespace: validate_namespace(namespace))
                     .create_resource(secret_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Secret', name)
      end
      
      def create_docker_registry_secret(name, server, username, password, email: nil, namespace: 'default')
        docker_config = {
          auths: {
            server => {
              username: username,
              password: password,
              email: email,
              auth: Base64.strict_encode64("#{username}:#{password}")
            }.compact
          }
        }
        
        create_secret(
          name,
          data: { '.dockerconfigjson' => Base64.strict_encode64(docker_config.to_json) },
          type: 'kubernetes.io/dockerconfigjson',
          namespace: namespace
        )
      end
      
      def create_tls_secret(name, cert_data, key_data, namespace: 'default')
        create_secret(
          name,
          data: {
            'tls.crt' => Base64.strict_encode64(cert_data),
            'tls.key' => Base64.strict_encode64(key_data)
          },
          type: 'kubernetes.io/tls',
          namespace: namespace
        )
      end
      
      def create_basic_auth_secret(name, username, password, namespace: 'default')
        create_secret(
          name,
          string_data: {
            'username' => username,
            'password' => password
          },
          type: 'kubernetes.io/basic-auth',
          namespace: namespace
        )
      end
      
      def update_secret(name, data: {}, string_data: {}, namespace: 'default')
        secret = get_secret(name, namespace)
        return nil unless secret
        
        secret.data = data unless data.empty?
        secret.stringData = string_data unless string_data.empty?
        
        core_v1_client.resource('secrets', namespace: validate_namespace(namespace))
                     .update_resource(secret)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Secret', name)
      end
      
      def delete_secret(name, namespace: 'default')
        core_v1_client.resource('secrets', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Secret', name)
      end
      
      # Utility methods
      def get_secret_data_decoded(name, namespace: 'default')
        secret = get_secret(name, namespace)
        return nil unless secret&.data
        
        decoded_data = {}
        secret.data.each do |key, encoded_value|
          decoded_data[key] = Base64.strict_decode64(encoded_value)
        end
        decoded_data
      rescue ArgumentError => e
        Rails.logger.error "Failed to decode secret data: #{e.message}"
        nil
      end
      
      def create_configmap_from_files(name, file_paths, namespace: 'default', labels: {})
        data = {}
        file_paths.each do |file_path|
          filename = File.basename(file_path)
          data[filename] = File.read(file_path)
        end
        
        create_configmap(name, data: data, namespace: namespace, labels: labels)
      rescue Errno::ENOENT => e
        Rails.logger.error "File not found when creating ConfigMap: #{e.message}"
        nil
      end
      
      def create_secret_from_files(name, file_paths, namespace: 'default', type: 'Opaque', labels: {})
        data = {}
        file_paths.each do |file_path|
          filename = File.basename(file_path)
          file_content = File.read(file_path)
          data[filename] = Base64.strict_encode64(file_content)
        end
        
        create_secret(name, data: data, type: type, namespace: namespace, labels: labels)
      rescue Errno::ENOENT => e
        Rails.logger.error "File not found when creating Secret: #{e.message}"
        nil
      end
    end
  end
end