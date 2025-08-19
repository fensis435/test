# app/services/kubernetes/job_service.rb
module Kubernetes
  class JobService < BaseService
    class << self
      # Job operations
      def list_jobs(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        batch_v1_client.resource('jobs', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Job', 'list')
      end
      
      def get_job(name, namespace: 'default')
        batch_v1_client.resource('jobs', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Job', name)
      end
      
      def create_job(spec, namespace: 'default')
        job_manifest = build_job_manifest(spec, namespace)
        batch_v1_client.resource('jobs', namespace: validate_namespace(namespace))
                      .create_resource(job_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Job', spec[:name])
      end
      
      def delete_job(name, namespace: 'default', propagation_policy: 'Background')
        options = { propagationPolicy: propagation_policy }
        batch_v1_client.resource('jobs', namespace: validate_namespace(namespace))
                      .delete_resource(name, **options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'Job', name)
      end
      
      def get_job_status(name, namespace: 'default')
        job = get_job(name, namespace)
        return nil unless job
        
        {
          active: job.status&.active || 0,
          succeeded: job.status&.succeeded || 0,
          failed: job.status&.failed || 0,
          start_time: job.status&.startTime,
          completion_time: job.status&.completionTime,
          conditions: job.status&.conditions,
          ready: job.status&.ready,
          completed: job_completed?(job),
          failed_job: job_failed?(job)
        }
      end
      
      def wait_for_job_completion(name, namespace: 'default', timeout: 3600)
        start_time = Time.current
        
        loop do
          job = get_job(name, namespace)
          return { success: false, reason: 'not_found' } unless job
          
          if job_completed?(job)
            return { success: true, reason: 'completed' }
          elsif job_failed?(job)
            return { success: false, reason: 'failed' }
          end
          
          if Time.current - start_time > timeout
            Rails.logger.warn "Timeout waiting for job #{name} to complete"
            return { success: false, reason: 'timeout' }
          end
          
          sleep 10
        end
      end
      
      def get_job_pods(name, namespace: 'default')
        job = get_job(name, namespace)
        return [] unless job
        
        # Jobs create pods with specific labels
        job_selector = job.spec&.selector&.matchLabels
        return [] unless job_selector
        
        label_selector = job_selector.map { |k, v| "#{k}=#{v}" }.join(',')
        PodService.list_pods(namespace: namespace, label_selector: label_selector)
      end
      
      def get_job_logs(name, namespace: 'default')
        pods = get_job_pods(name, namespace)
        return [] if pods.empty?
        
        logs = []
        pods.each do |pod|
          pod_logs = PodService.get_pod_logs(pod.metadata.name, namespace: namespace)
          logs << {
            pod_name: pod.metadata.name,
            logs: pod_logs
          }
        end
        logs
      end
      
      # CronJob operations
      def list_cronjobs(namespace: 'default', label_selector: nil)
        options = {}
        options[:labelSelector] = label_selector if label_selector.present?
        
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace)).list(**options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob', 'list')
      end
      
      def get_cronjob(name, namespace: 'default')
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace)).get(name)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob', name)
      end
      
      def create_cronjob(spec, namespace: 'default')
        cronjob_manifest = build_cronjob_manifest(spec, namespace)
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace))
                      .create_resource(cronjob_manifest)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob', spec[:name])
      end
      
      def update_cronjob(name, spec, namespace: 'default')
        cronjob = get_cronjob(name, namespace)
        return nil unless cronjob
        
        cronjob.spec.schedule = spec[:schedule] if spec[:schedule]
        cronjob.spec.suspend = spec[:suspend] if spec.key?(:suspend)
        cronjob.spec.jobTemplate = spec[:job_template] if spec[:job_template]
        
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace))
                      .update_resource(cronjob)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob', name)
      end
      
      def delete_cronjob(name, namespace: 'default', propagation_policy: 'Background')
        options = { propagationPolicy: propagation_policy }
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace))
                      .delete_resource(name, **options)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob', name)
      end
      
      def suspend_cronjob(name, namespace: 'default')
        cronjob = get_cronjob(name, namespace)
        return nil unless cronjob
        
        cronjob.spec.suspend = true
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace))
                      .update_resource(cronjob)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob suspend', name)
      end
      
      def resume_cronjob(name, namespace: 'default')
        cronjob = get_cronjob(name, namespace)
        return nil unless cronjob
        
        cronjob.spec.suspend = false
        batch_v1_client.resource('cronjobs', namespace: validate_namespace(namespace))
                      .update_resource(cronjob)
      rescue K8s::Error => e
        handle_k8s_error(e, 'CronJob resume', name)
      end
      
      def trigger_cronjob_manually(name, namespace: 'default')
        cronjob = get_cronjob(name, namespace)
        return nil unless cronjob
        
        # Create a job from the cronjob template
        job_name = "#{name}-manual-#{Time.current.to_i}"
        job_spec = cronjob.spec.jobTemplate.spec.to_h
        job_spec[:name] = job_name
        
        create_job(job_spec, namespace)
      end
      
      def get_cronjob_status(name, namespace: 'default')
        cronjob = get_cronjob(name, namespace)
        return nil unless cronjob
        
        {
          schedule: cronjob.spec&.schedule,
          suspend: cronjob.spec&.suspend || false,
          active: cronjob.status&.active || [],
          last_schedule_time: cronjob.status&.lastScheduleTime,
          last_successful_time: cronjob.status&.lastSuccessfulTime
        }
      end
      
      def get_cronjob_jobs(name, namespace: 'default')
        # Find jobs created by this cronjob
        label_selector = "job-name"
        jobs = list_jobs(namespace: namespace, label_selector: label_selector)
        
        # Filter jobs that belong to this cronjob
        jobs.select do |job|
          job.metadata&.ownerReferences&.any? do |ref|
            ref.kind == 'CronJob' && ref.name == name
          end
        end
      end
      
      private
      
      def build_job_manifest(spec, namespace)
        {
          apiVersion: 'batch/v1',
          kind: 'Job',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            template: {
              spec: {
                containers: spec[:containers] || [],
                restartPolicy: spec[:restart_policy] || 'Never',
                volumes: spec[:volumes],
                serviceAccountName: spec[:service_account_name],
                nodeSelector: spec[:node_selector],
                tolerations: spec[:tolerations],
                affinity: spec[:affinity]
              }.compact
            },
            completions: spec[:completions],
            parallelism: spec[:parallelism],
            activeDeadlineSeconds: spec[:active_deadline_seconds],
            backoffLimit: spec[:backoff_limit] || 6,
            ttlSecondsAfterFinished: spec[:ttl_seconds_after_finished]
          }.compact
        }
      end
      
      def build_cronjob_manifest(spec, namespace)
        {
          apiVersion: 'batch/v1',
          kind: 'CronJob',
          metadata: {
            name: spec[:name],
            namespace: validate_namespace(namespace),
            labels: build_labels(spec[:labels] || {}),
            annotations: build_annotations(spec[:annotations] || {})
          },
          spec: {
            schedule: spec[:schedule],
            jobTemplate: {
              spec: build_job_manifest(spec[:job_template] || {}, namespace)[:spec]
            },
            suspend: spec[:suspend] || false,
            concurrencyPolicy: spec[:concurrency_policy] || 'Allow',
            failedJobsHistoryLimit: spec[:failed_jobs_history_limit] || 1,
            successfulJobsHistoryLimit: spec[:successful_jobs_history_limit] || 3,
            startingDeadlineSeconds: spec[:starting_deadline_seconds]
          }.compact
        }
      end
      
      def job_completed?(job)
        return false unless job.status&.conditions
        
        completion_condition = job.status.conditions.find { |c| c.type == 'Complete' }
        completion_condition&.status == 'True'
      end
      
      def job_failed?(job)
        return false unless job.status&.conditions
        
        failed_condition = job.status.conditions.find { |c| c.type == 'Failed' }
        failed_condition&.status == 'True'
      end
    end
  end
end