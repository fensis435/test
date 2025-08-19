# app/services/kubernetes/namespace_service.rb
module Kubernetes
  class NamespaceService < BaseService
    class << self
      def list_namespaces(label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        core_v1_client.resource('namespaces').list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Namespace', 'list')
      end
      
      def get_namespace(name)
        core_v1_client.resource('namespaces').get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Namespace', name)
      end
      
      def create_namespace(name, labels: {}, annotations: {})
        namespace_manifest = {
          apiVersion: 'v1',
          kind: 'Namespace',
          metadata: {
            name: name,
            labels: build_labels(labels),
            annotations: build_annotations(annotations)
          }
        }
        
        core_v1_client.resource('namespaces').create_resource(namespace_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Namespace', name)
      end
      
      def delete_namespace(name)
        core_v1_client.resource('namespaces').delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Namespace', name)
      end
      
      def get_namespace_status(name)
        namespace = get_namespace(name)
        return nil unless namespace
        
        {
          phase: namespace.status&.phase,
          conditions: namespace.status&.conditions
        }
      end
      
      def wait_for_namespace_termination(name, timeout: 300)
        start_time = Time.current
        
        loop do
          namespace = get_namespace(name)
          return true unless namespace
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for namespace #{name} to terminate"
            return false
          end
          
          sleep 5
        end
      end
      
      def set_namespace_resource_quota(name, spec)
        quota_name = "#{name}-quota"
        quota_manifest = {
          apiVersion: 'v1',
          kind: 'ResourceQuota',
          metadata: {
            name: quota_name,
            namespace: name,
            labels: build_labels({ 'managed-by' => 'namespace-service' })
          },
          spec: {
            hard: spec
          }
        }
        
        core_v1_client.resource('resourcequotas', namespace: name).create_resource(quota_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ResourceQuota', quota_name)
      end
      
      def set_namespace_limit_range(name, limits)
        limit_range_name = "#{name}-limits"
        limit_manifest = {
          apiVersion: 'v1',
          kind: 'LimitRange',
          metadata: {
            name: limit_range_name,
            namespace: name,
            labels: build_labels({ 'managed-by' => 'namespace-service' })
          },
          spec: {
            limits: limits
          }
        }
        
        core_v1_client.resource('limitranges', namespace: name).create_resource(limit_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'LimitRange', limit_range_name)
      end
    end
  end
  
  # RBAC Service for managing roles, rolebindings, clusterroles, etc.
  class RbacService < BaseService
    class << self
      # ServiceAccount operations
      def list_service_accounts(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        core_v1_client.resource('serviceaccounts', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount', 'list')
      end
      
      def get_service_account(name, namespace: 'default')
        core_v1_client.resource('serviceaccounts', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount', name)
      end
      
      def create_service_account(name, namespace: 'default', labels: {}, annotations: {}, automount_token: true)
        sa_manifest = {
          apiVersion: 'v1',
          kind: 'ServiceAccount',
          metadata: {
            name: name,
            namespace: validate_namespace(namespace),
            labels: build_labels(labels),
            annotations: build_annotations(annotations)
          },
          automountServiceAccountToken: automount_token
        }
        
        core_v1_client.resource('serviceaccounts', namespace: validate_namespace(namespace))
                     .create_resource(sa_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount', name)
      end
      
      def delete_service_account(name, namespace: 'default')
        core_v1_client.resource('serviceaccounts', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount', name)
      end
      
      # Role operations
      def list_roles(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        rbac_v1_client.resource('roles', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Role', 'list')
      end
      
      def get_role(name, namespace: 'default')
        rbac_v1_client.resource('roles', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Role', name)
      end
      
      def create_role(name, rules, namespace: 'default', labels: {}, annotations: {})
        role_manifest = {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'Role',
          metadata: {
            name: name,
            namespace: validate_namespace(namespace),
            labels: build_labels(labels),
            annotations: build_annotations(annotations)
          },
          rules: rules
        }
        
        rbac_v1_client.resource('roles', namespace: validate_namespace(namespace))
                     .create_resource(role_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Role', name)
      end
      
      def delete_role(name, namespace: 'default')
        rbac_v1_client.resource('roles', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Role', name)
      end
      
      # ClusterRole operations
      def list_cluster_roles(label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        rbac_v1_client.resource('clusterroles').list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRole', 'list')
      end
      
      def get_cluster_role(name)
        rbac_v1_client.resource('clusterroles').get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRole', name)
      end
      
      def create_cluster_role(name, rules, labels: {}, annotations: {})
        cluster_role_manifest = {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'ClusterRole',
          metadata: {
            name: name,
            labels: build_labels(labels),
            annotations: build_annotations(annotations)
          },
          rules: rules
        }
        
        rbac_v1_client.resource('clusterroles').create_resource(cluster_role_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRole', name)
      end
      
      def delete_cluster_role(name)
        rbac_v1_client.resource('clusterroles').delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRole', name)
      end
      
      # RoleBinding operations
      def list_role_bindings(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        rbac_v1_client.resource('rolebindings', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'RoleBinding', name)
      end
      
      def delete_role_binding(name, namespace: 'default')
        rbac_v1_client.resource('rolebindings', namespace: validate_namespace(namespace))
                     .delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'RoleBinding', name)
      end
      
      # ClusterRoleBinding operations
      def list_cluster_role_bindings(label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        rbac_v1_client.resource('clusterrolebindings').list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRoleBinding', 'list')
      end
      
      def create_cluster_role_binding(name, cluster_role_name, subjects, labels: {})
        role_ref = {
          apiGroup: 'rbac.authorization.k8s.io',
          kind: 'ClusterRole',
          name: cluster_role_name
        }
        
        cluster_role_binding_manifest = {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'ClusterRoleBinding',
          metadata: {
            name: name,
            labels: build_labels(labels)
          },
          roleRef: role_ref,
          subjects: subjects
        }
        
        rbac_v1_client.resource('clusterrolebindings').create_resource(cluster_role_binding_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRoleBinding', name)
      end
      
      def delete_cluster_role_binding(name)
        rbac_v1_client.resource('clusterrolebindings').delete_resource(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ClusterRoleBinding', name)
      end
      
      # Utility methods for common RBAC patterns
      def create_service_account_with_role(sa_name, role_name, rules, namespace: 'default')
        # Create ServiceAccount
        create_service_account(sa_name, namespace: namespace)
        
        # Create Role
        create_role(role_name, rules, namespace: namespace)
        
        # Create RoleBinding
        subjects = [
          {
            kind: 'ServiceAccount',
            name: sa_name,
            namespace: validate_namespace(namespace)
          }
        ]
        
        create_role_binding("#{sa_name}-binding", role_name, subjects, namespace: namespace)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount with Role creation', sa_name)
      end
      
      def create_service_account_with_cluster_role(sa_name, cluster_role_name, namespace: 'default')
        # Create ServiceAccount
        create_service_account(sa_name, namespace: namespace)
        
        # Create ClusterRoleBinding
        subjects = [
          {
            kind: 'ServiceAccount',
            name: sa_name,
            namespace: validate_namespace(namespace)
          }
        ]
        
        create_cluster_role_binding("#{sa_name}-cluster-binding", cluster_role_name, subjects)
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount with ClusterRole creation', sa_name)
      end
      
      def get_service_account_token(sa_name, namespace: 'default')
        # In Kubernetes 1.24+, tokens are not automatically created
        # You need to create a secret manually or use TokenRequest API
        token_secret_name = "#{sa_name}-token"
        
        token_secret_manifest = {
          apiVersion: 'v1',
          kind: 'Secret',
          metadata: {
            name: token_secret_name,
            namespace: validate_namespace(namespace),
            annotations: {
              'kubernetes.io/service-account.name' => sa_name
            }
          },
          type: 'kubernetes.io/service-account-token'
        }
        
        secret = core_v1_client.resource('secrets', namespace: validate_namespace(namespace))
                              .create_resource(token_secret_manifest)
        
        # Wait for token to be populated
        sleep 2
        
        secret = core_v1_client.resource('secrets', namespace: validate_namespace(namespace)).get(token_secret_name)
        Base64.strict_decode64(secret.data['token']) if secret.data && secret.data['token']
      rescue K8s::Error => e
        handle_k8s_error(e, 'ServiceAccount token creation', sa_name)
      end
      
      # Common role rule builders
      def build_pod_management_rules
        [
          {
            apiGroups: [''],
            resources: ['pods'],
            verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
          },
          {
            apiGroups: [''],
            resources: ['pods/log'],
            verbs: ['get', 'list']
          },
          {
            apiGroups: [''],
            resources: ['pods/exec'],
            verbs: ['create']
          }
        ]
      end
      
      def build_deployment_management_rules
        [
          {
            apiGroups: ['apps'],
            resources: ['deployments'],
            verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
          },
          {
            apiGroups: ['apps'],
            resources: ['deployments/scale'],
            verbs: ['get', 'update', 'patch']
          }
        ]
      end
      
      def build_service_management_rules
        [
          {
            apiGroups: [''],
            resources: ['services'],
            verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
          },
          {
            apiGroups: [''],
            resources: ['endpoints'],
            verbs: ['get', 'list', 'watch']
          }
        ]
      end
      
      def build_configmap_secret_management_rules
        [
          {
            apiGroups: [''],
            resources: ['configmaps'],
            verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
          },
          {
            apiGroups: [''],
            resources: ['secrets'],
            verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
          }
        ]
      end
      
      def build_readonly_rules
        [
          {
            apiGroups: [''],
            resources: ['*'],
            verbs: ['get', 'list', 'watch']
          },
          {
            apiGroups: ['apps'],
            resources: ['*'],
            verbs: ['get', 'list', 'watch']
          },
          {
            apiGroups: ['networking.k8s.io'],
            resources: ['*'],
            verbs: ['get', 'list', 'watch']
          }
        ]
      end
    end
  end
end 'list')
      end
      
      def create_role_binding(name, role_name, subjects, namespace: 'default', role_kind: 'Role', labels: {})
        role_ref = {
          apiGroup: 'rbac.authorization.k8s.io',
          kind: role_kind,
          name: role_name
        }
        
        role_binding_manifest = {
          apiVersion: 'rbac.authorization.k8s.io/v1',
          kind: 'RoleBinding',
          metadata: {
            name: name,
            namespace: validate_namespace(namespace),
            labels: build_labels(labels)
          },
          roleRef: role_ref,
          subjects: subjects
        }
        
        rbac_v1_client.resource('rolebindings', namespace: validate_namespace(namespace))
                     .create_resource(role_binding_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'RoleBinding',