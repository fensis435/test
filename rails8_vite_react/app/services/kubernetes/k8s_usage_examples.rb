# app/services/kubernetes/usage_examples.rb
# This file contains usage examples for the Kubernetes services

module Kubernetes
  class UsageExamples
    # Example 1: Deploy a simple web application
    def self.deploy_web_app(name, image, namespace: 'default', replicas: 3, port: 80)
      # Create namespace if it doesn't exist
      NamespaceService.create_namespace(namespace) rescue nil
      
      # Create deployment
      deployment_spec = {
        name: name,
        replicas: replicas,
        containers: [
          {
            name: name,
            image: image,
            ports: [
              {
                containerPort: port,
                protocol: 'TCP'
              }
            ],
            resources: {
              requests: {
                cpu: '100m',
                memory: '128Mi'
              },
              limits: {
                cpu: '500m',
                memory: '512Mi'
              }
            }
          }
        ]
      }
      
      deployment = DeploymentService.create_deployment(deployment_spec, namespace: namespace)
      return nil unless deployment
      
      # Create service
      service_spec = {
        name: "#{name}-service",
        selector: { app: name },
        ports: [
          {
            port: 80,
            targetPort: port,
            protocol: 'TCP'
          }
        ],
        type: 'ClusterIP'
      }
      
      service = ServiceService.create_service(service_spec, namespace: namespace)
      
      # Create HPA
      hpa_spec = {
        name: "#{name}-hpa",
        target_name: name,
        min_replicas: 2,
        max_replicas: 10,
        target_cpu_percentage: 70
      }
      
      hpa = AutoscalingService.create_hpa(hpa_spec, namespace: namespace)
      
      {
        deployment: deployment,
        service: service,
        hpa: hpa
      }
    end
    
    # Example 2: Create a job for data processing
    def self.create_data_processing_job(name, image, command, namespace: 'default')
      job_spec = {
        name: name,
        containers: [
          {
            name: name,
            image: image,
            command: command,
            resources: {
              requests: {
                cpu: '500m',
                memory: '1Gi'
              },
              limits: {
                cpu: '2',
                memory: '4Gi'
              }
            }
          }
        ],
        restart_policy: 'Never',
        backoff_limit: 3,
        ttl_seconds_after_finished: 3600
      }
      
      JobService.create_job(job_spec, namespace: namespace)
    end
    
    # Example 3: Set up a cron job for regular maintenance
    def self.create_maintenance_cronjob(name, image, schedule, namespace: 'default')
      cronjob_spec = {
        name: name,
        schedule: schedule,
        job_template: {
          name: "#{name}-job",
          containers: [
            {
              name: 'maintenance',
              image: image,
              command: ['/bin/sh', '-c', 'echo "Running maintenance task"'],
              resources: {
                requests: {
                  cpu: '100m',
                  memory: '256Mi'
                }
              }
            }
          ],
          restart_policy: 'OnFailure',
          backoff_limit: 2
        },
        concurrency_policy: 'Forbid',
        failed_jobs_history_limit: 3,
        successful_jobs_history_limit: 5
      }
      
      JobService.create_cronjob(cronjob_spec, namespace: namespace)
    end
    
    # Example 4: Deploy application with persistent storage
    def self.deploy_stateful_app(name, image, storage_size: '10Gi', namespace: 'default')
      # Create PVC
      pvc_spec = {
        name: "#{name}-storage",
        access_modes: ['ReadWriteOnce'],
        resources: {
          requests: {
            storage: storage_size
          }
        }
      }
      
      pvc = VolumeService.create_persistent_volume_claim(pvc_spec, namespace: namespace)
      return nil unless pvc
      
      # Create deployment with volume
      deployment_spec = {
        name: name,
        replicas: 1,
        containers: [
          {
            name: name,
            image: image,
            volumeMounts: [
              {
                name: 'storage',
                mountPath: '/data'
              }
            ],
            resources: {
              requests: {
                cpu: '200m',
                memory: '512Mi'
              }
            }
          }
        ],
        volumes: [
          {
            name: 'storage',
            persistentVolumeClaim: {
              claimName: "#{name}-storage"
            }
          }
        ]
      }
      
      deployment = DeploymentService.create_deployment(deployment_spec, namespace: namespace)
      
      {
        pvc: pvc,
        deployment: deployment
      }
    end
    
    # Example 5: Create a service account with specific permissions
    def self.create_service_account_with_permissions(sa_name, namespace: 'default')
      # Define rules for pod management
      rules = [
        {
          apiGroups: [''],
          resources: ['pods'],
          verbs: ['get', 'list', 'watch', 'create', 'update', 'patch', 'delete']
        },
        {
          apiGroups: ['apps'],
          resources: ['deployments'],
          verbs: ['get', 'list', 'watch', 'update', 'patch']
        },
        {
          apiGroups: [''],
          resources: ['configmaps', 'secrets'],
          verbs: ['get', 'list', 'watch']
        }
      ]
      
      RbacService.create_service_account_with_role(
        sa_name,
        "#{sa_name}-role",
        rules,
        namespace: namespace
      )
    end
    
    # Example 6: Deploy with ingress
    def self.deploy_with_ingress(name, image, host, namespace: 'default')
      # Deploy the application
      app_resources = deploy_web_app(name, image, namespace: namespace)
      return nil unless app_resources
      
      # Create ingress
      ingress = IngressService.create_simple_ingress(
        "#{name}-ingress",
        host,
        "#{name}-service",
        80,
        namespace: namespace
      )
      
      app_resources.merge(ingress: ingress)
    end
    
    # Example 7: Deploy with SSL termination
    def self.deploy_with_ssl(name, image, host, tls_secret_name, namespace: 'default')
      # Deploy the application
      app_resources = deploy_web_app(name, image, namespace: namespace)
      return nil unless app_resources
      
      # Create TLS ingress
      ingress = IngressService.create_tls_ingress(
        "#{name}-ingress",
        host,
        "#{name}-service",
        80,
        tls_secret_name,
        namespace: namespace
      )
      
      app_resources.merge(ingress: ingress)
    end
    
    # Example 8: Create development environment
    def self.create_dev_environment(app_name, namespace: nil)
      namespace ||= "#{app_name}-dev"
      
      # Create namespace
      NamespaceService.create_namespace(
        namespace,
        labels: { environment: 'development', app: app_name }
      )
      
      # Set resource quotas for development
      resource_quota = {
        'requests.cpu' => '2',
        'requests.memory' => '4Gi',
        'limits.cpu' => '4',
        'limits.memory' => '8Gi',
        'persistentvolumeclaims' => '10'
      }
      
      NamespaceService.set_namespace_resource_quota(namespace, resource_quota)
      
      # Set limit ranges
      limit_ranges = [
        {
          type: 'Container',
          default: {
            cpu: '200m',
            memory: '256Mi'
          },
          defaultRequest: {
            cpu: '100m',
            memory: '128Mi'
          }
        }
      ]
      
      NamespaceService.set_namespace_limit_range(namespace, limit_ranges)
      
      # Create service account for development
      create_service_account_with_permissions("#{app_name}-dev-sa", namespace: namespace)
      
      namespace
    end
    
    # Example 9: Backup and restore operations
    def self.backup_application_configs(app_name, namespace: 'default')
      backup_data = {}
      
      # Backup ConfigMaps
      configmaps = ConfigService.list_configmaps(namespace: namespace, label_selector: "app=#{app_name}")
      backup_data[:configmaps] = configmaps if configmaps
      
      # Backup Secrets (metadata only, not actual secret data for security)
      secrets = ConfigService.list_secrets(namespace: namespace, label_selector: "app=#{app_name}")
      backup_data[:secrets_metadata] = secrets&.map do |secret|
        {
          name: secret.metadata.name,
          type: secret.type,
          labels: secret.metadata.labels,
          annotations: secret.metadata.annotations
        }
      end
      
      # Backup Service definitions
      services = ServiceService.list_services(namespace: namespace, label_selector: "app=#{app_name}")
      backup_data[:services] = services if services
      
      # Backup Ingress definitions
      ingresses = IngressService.list_ingresses(namespace: namespace, label_selector: "app=#{app_name}")
      backup_data[:ingresses] = ingresses if ingresses
      
      backup_data
    end
    
    # Example 10: Health monitoring and alerting
    def self.check_application_health(app_name, namespace: 'default')
      health_report = {
        app_name: app_name,
        namespace: namespace,
        timestamp: Time.current,
        status: 'healthy',
        issues: []
      }
      
      # Check deployment status
      deployment = DeploymentService.get_deployment(app_name, namespace: namespace)
      if deployment
        deployment_status = DeploymentService.get_deployment_status(app_name, namespace: namespace)
        unless deployment_status[:ready]
          health_report[:issues] << "Deployment #{app_name} is not ready"
          health_report[:status] = 'unhealthy'
        end
        health_report[:deployment_status] = deployment_status
      else
        health_report[:issues] << "Deployment #{app_name} not found"
        health_report[:status] = 'critical'
      end
      
      # Check service endpoints
      service = ServiceService.get_service("#{app_name}-service", namespace: namespace)
      if service
        endpoints = ServiceService.get_service_endpoints("#{app_name}-service", namespace: namespace)
        if endpoints&.subsets&.empty?
          health_report[:issues] << "Service #{app_name}-service has no endpoints"
          health_report[:status] = 'warning'
        end
      end
      
      # Check HPA status
      hpa = AutoscalingService.get_hpa("#{app_name}-hpa", namespace: namespace)
      if hpa
        hpa_status = AutoscalingService.get_hpa_status("#{app_name}-hpa", namespace: namespace)
        health_report[:hpa_status] = hpa_status
      end
      
      # Check pod status
      pods = DeploymentService.get_deployment_pods(app_name, namespace: namespace)
      if pods
        failed_pods = pods.select { |pod| pod.status&.phase == 'Failed' }
        pending_pods = pods.select { |pod| pod.status&.phase == 'Pending' }
        
        if failed_pods.any?
          health_report[:issues] << "Failed pods: #{failed_pods.map { |p| p.metadata.name }.join(', ')}"
          health_report[:status] = 'critical'
        end
        
        if pending_pods.any?
          health_report[:issues] << "Pending pods: #{pending_pods.map { |p| p.metadata.name }.join(', ')}"
          health_report[:status] = 'warning' if health_report[:status] == 'healthy'
        end
        
        health_report[:pod_summary] = {
          total: pods.length,
          running: pods.count { |p| p.status&.phase == 'Running' },
          pending: pending_pods.length,
          failed: failed_pods.length
        }
      end
      
      health_report
    end
    
    # Example 11: Blue-Green deployment
    def self.blue_green_deployment(app_name, new_image, namespace: 'default')
      # Get current deployment
      current_deployment = DeploymentService.get_deployment(app_name, namespace: namespace)
      return nil unless current_deployment
      
      # Create green deployment
      green_name = "#{app_name}-green"
      green_spec = {
        name: green_name,
        replicas: current_deployment.spec.replicas,
        containers: current_deployment.spec.template.spec.containers.map do |container|
          container_hash = container.to_h
          container_hash[:image] = new_image if container_hash[:name] == app_name
          container_hash
        end
      }
      
      green_deployment = DeploymentService.create_deployment(green_spec, namespace: namespace)
      return nil unless green_deployment
      
      # Wait for green deployment to be ready
      unless DeploymentService.wait_for_deployment_ready(green_name, namespace: namespace)
        Rails.logger.error "Green deployment failed to become ready"
        DeploymentService.delete_deployment(green_name, namespace: namespace)
        return nil
      end
      
      # Switch service to point to green deployment
      service = ServiceService.get_service("#{app_name}-service", namespace: namespace)
      if service
        ServiceService.update_service(
          "#{app_name}-service",
          { selector: { app: green_name } },
          namespace: namespace
        )
      end
      
      # Clean up old deployment
      DeploymentService.delete_deployment(app_name, namespace: namespace)
      
      # Rename green deployment to original name
      # Note: This is simplified - in practice, you might keep both for rollback
      
      {
        old_deployment: app_name,
        new_deployment: green_name,
        switched_at: Time.current
      }
    end
    
    # Example 12: Resource cleanup
    def self.cleanup_application(app_name, namespace: 'default')
      results = {}
      
      # Delete HPA
      results[:hpa] = AutoscalingService.delete_hpa("#{app_name}-hpa", namespace: namespace)
      
      # Delete Ingress
      results[:ingress] = IngressService.delete_ingress("#{app_name}-ingress", namespace: namespace)
      
      # Delete Service
      results[:service] = ServiceService.delete_service("#{app_name}-service", namespace: namespace)
      
      # Delete Deployment
      results[:deployment] = DeploymentService.delete_deployment(app_name, namespace: namespace)
      
      # Delete ConfigMaps
      configmaps = ConfigService.list_configmaps(namespace: namespace, label_selector: "app=#{app_name}")
      if configmaps
        configmaps.each do |cm|
          ConfigService.delete_configmap(cm.metadata.name, namespace: namespace)
        end
        results[:configmaps] = configmaps.length
      end
      
      # Delete Secrets
      secrets = ConfigService.list_secrets(namespace: namespace, label_selector: "app=#{app_name}")
      if secrets
        secrets.each do |secret|
          ConfigService.delete_secret(secret.metadata.name, namespace: namespace)
        end
        results[:secrets] = secrets.length
      end
      
      # Delete PVCs
      pvcs = VolumeService.list_persistent_volume_claims(namespace: namespace, label_selector: "app=#{app_name}")
      if pvcs
        pvcs.each do |pvc|
          VolumeService.delete_persistent_volume_claim(pvc.metadata.name, namespace: namespace)
        end
        results[:pvcs] = pvcs.length
      end
      
      results
    end
  end
end