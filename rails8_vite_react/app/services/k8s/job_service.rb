class K8s::JobService < K8s::BaseService
  def create(job_name:, namespace:, image:, command: nil, args: nil, env: {}, restart_policy: 'Never', ttl_seconds_after_finished: nil)
    handle_k8s_error do
      job_spec = {
        metadata: {
          name: job_name,
          namespace: namespace,
          labels: {
            'managed-by' => 'rails-k8s-controller',
            'job' => job_name
          }
        },
        spec: {
          template: {
            spec: {
              restartPolicy: restart_policy,
              containers: [{
                name: job_name,
                image: image,
                env: env.map { |k, v| { name: k.to_s, value: v.to_s } }
              }]
            }
          }
        }
      }
      
      # Add command and args if provided
      if command.present?
        job_spec[:spec][:template][:spec][:containers][0][:command] = Array(command)
      end
      
      if args.present?
        job_spec[:spec][:template][:spec][:containers][0][:args] = Array(args)
      end
      
      # Add TTL if specified
      if ttl_seconds_after_finished.present?
        job_spec[:spec][:ttlSecondsAfterFinished] = ttl_seconds_after_finished
      end
      
      job = Kubeclient::Resource.new(job_spec)
      k8s_batch_client.create_job(job)
      Rails.logger.info "Created Job: #{job_name} in namespace: #{namespace}"
    end
  end

  def delete(job_name:, namespace:, delete_pods: true)
    handle_k8s_error do
      if delete_pods
        # Delete with cascade to remove pods
        k8s_batch_client.delete_job(job_name, namespace, 
          propagation_policy: 'Foreground')
      else
        k8s_batch_client.delete_job(job_name, namespace, 
          propagation_policy: 'Orphan')
      end
      Rails.logger.info "Deleted Job: #{job_name} in namespace: #{namespace}"
    end
  end

  def status(job_name:, namespace:)
    handle_k8s_error do
      job = k8s_batch_client.get_job(job_name, namespace)
      {
        'metadata' => {
          'name' => job.metadata.name,
          'namespace' => job.metadata.namespace,
          'creationTimestamp' => job.metadata.creationTimestamp
        },
        'status' => {
          'active' => job.status.active,
          'succeeded' => job.status.succeeded,
          'failed' => job.status.failed,
          'startTime' => job.status.startTime,
          'completionTime' => job.status.completionTime,
          'conditions' => job.status.conditions&.map(&:to_h)
        }
      }
    end
  end

  def wait_for_completion(job_name:, namespace:, timeout: 300)
    handle_k8s_error do
      start_time = Time.current
      
      loop do
        job = k8s_batch_client.get_job(job_name, namespace)
        
        # Check if job completed successfully
        if job.status.succeeded.to_i > 0
          Rails.logger.info "Job #{job_name} completed successfully in namespace: #{namespace}"
          return { status: 'succeeded', job: job }
        end
        
        # Check if job failed
        if job.status.failed.to_i > 0
          Rails.logger.warn "Job #{job_name} failed in namespace: #{namespace}"
          return { status: 'failed', job: job }
        end
        
        if Time.current - start_time > timeout
          raise K8sError, "Timeout waiting for Job #{job_name} completion"
        end
        
        sleep 5
      end
    end
  end

  def get_pods(job_name:, namespace:)
    handle_k8s_error do
      pods = k8s_client.get_pods(
        namespace: namespace,
        label_selector: "job-name=#{job_name}"
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
              'conditions' => pod.status.conditions&.map(&:to_h),
              'containerStatuses' => pod.status.containerStatuses&.map(&:to_h)
            }
          }
        end
      }
    end
  end

  def get_logs(job_name:, namespace:, container: nil, tail_lines: nil)
    handle_k8s_error do
      pods = get_pods(job_name: job_name, namespace: namespace)
      return { logs: 'No pods found for job' } if pods['items'].empty?
      
      pod_name = pods['items'].first['metadata']['name']
      
      log_options = {}
      log_options[:container] = container if container.present?
      log_options[:tailLines] = tail_lines if tail_lines.present?
      
      logs = k8s_client.get_pod_log(pod_name, namespace, log_options)
      { logs: logs, pod_name: pod_name }
    end
  end

  def list(namespace:, label_selector: nil)
    handle_k8s_error do
      options = { namespace: namespace }
      options[:label_selector] = label_selector if label_selector.present?
      
      jobs = k8s_batch_client.get_jobs(options)
      {
        'items' => jobs.map do |job|
          {
            'metadata' => {
              'name' => job.metadata.name,
              'namespace' => job.metadata.namespace,
              'creationTimestamp' => job.metadata.creationTimestamp
            },
            'status' => {
              'active' => job.status.active,
              'succeeded' => job.status.succeeded,
              'failed' => job.status.failed,
              'startTime' => job.status.startTime,
              'completionTime' => job.status.completionTime
            }
          }
        end
      }
    end
  end

  def exists?(job_name:, namespace:)
    handle_k8s_error do
      k8s_batch_client.get_job(job_name, namespace)
      true
    end
  rescue K8sError
    false
  end

  private

  def k8s_batch_client
    @k8s_batch_client ||= Kubeclient::Client.new(
      Rails.application.config.k8s_api_endpoint,
      'batch/v1',
      auth_options: k8s_auth_options,
      ssl_options: k8s_ssl_options
    )
  end
end
