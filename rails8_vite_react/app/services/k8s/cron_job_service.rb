class K8s::CronJobService < K8s::BaseService
  def create(cron_job_name:, namespace:, schedule:, image:, command: nil, args: nil, env: {}, 
             suspend: false, concurrency_policy: 'Allow', failed_jobs_history_limit: 1, 
             successful_jobs_history_limit: 3, starting_deadline_seconds: nil)
    handle_k8s_error do
      cron_job_spec = {
        metadata: {
          name: cron_job_name,
          namespace: namespace,
          labels: {
            'managed-by' => 'rails-k8s-controller',
            'cronjob' => cron_job_name
          }
        },
        spec: {
          schedule: schedule,
          suspend: suspend,
          concurrencyPolicy: concurrency_policy,
          failedJobsHistoryLimit: failed_jobs_history_limit,
          successfulJobsHistoryLimit: successful_jobs_history_limit,
          jobTemplate: {
            spec: {
              template: {
                spec: {
                  restartPolicy: 'OnFailure',
                  containers: [{
                    name: cron_job_name,
                    image: image,
                    env: env.map { |k, v| { name: k.to_s, value: v.to_s } }
                  }]
                }
              }
            }
          }
        }
      }
      
      # Add command and args if provided
      if command.present?
        cron_job_spec[:spec][:jobTemplate][:spec][:template][:spec][:containers][0][:command] = Array(command)
      end
      
      if args.present?
        cron_job_spec[:spec][:jobTemplate][:spec][:template][:spec][:containers][0][:args] = Array(args)
      end
      
      # Add starting deadline if specified
      if starting_deadline_seconds.present?
        cron_job_spec[:spec][:startingDeadlineSeconds] = starting_deadline_seconds
      end
      
      cron_job = Kubeclient::Resource.new(cron_job_spec)
      k8s_batch_client.create_cron_job(cron_job)
      Rails.logger.info "Created CronJob: #{cron_job_name} in namespace: #{namespace}"
    end
  end

  def update(cron_job_name:, namespace:, schedule: nil, suspend: nil, image: nil, 
             command: nil, args: nil, env: nil, concurrency_policy: nil)
    handle_k8s_error do
      cron_job = k8s_batch_client.get_cron_job(cron_job_name, namespace)
      
      # Update schedule if provided
      cron_job.spec.schedule = schedule if schedule.present?
      
      # Update suspend state if provided
      cron_job.spec.suspend = suspend unless suspend.nil?
      
      # Update concurrency policy if provided
      cron_job.spec.concurrencyPolicy = concurrency_policy if concurrency_policy.present?
      
      # Update container spec if provided
      container = cron_job.spec.jobTemplate.spec.template.spec.containers[0]
      
      if image.present?
        container.image = image
      end
      
      if command.present?
        container.command = Array(command)
      end
      
      if args.present?
        container.args = Array(args)
      end
      
      if env.present?
        container.env = env.map { |k, v| { name: k.to_s, value: v.to_s } }
      end
      
      k8s_batch_client.update_cron_job(cron_job)
      Rails.logger.info "Updated CronJob: #{cron_job_name} in namespace: #{namespace}"
    end
  end

  def delete(cron_job_name:, namespace:, delete_jobs: true)
    handle_k8s_error do
      if delete_jobs
        # Delete with cascade to remove jobs
        k8s_batch_client.delete_cron_job(cron_job_name, namespace, 
          propagation_policy: 'Foreground')
      else
        k8s_batch_client.delete_cron_job(cron_job_name, namespace, 
          propagation_policy: 'Orphan')
      end
      Rails.logger.info "Deleted CronJob: #{cron_job_name} in namespace: #{namespace}"
    end
  end

  def suspend(cron_job_name:, namespace:)
    handle_k8s_error do
      cron_job = k8s_batch_client.get_cron_job(cron_job_name, namespace)
      cron_job.spec.suspend = true
      k8s_batch_client.update_cron_job(cron_job)
      Rails.logger.info "Suspended CronJob: #{cron_job_name} in namespace: #{namespace}"
    end
  end

  def resume(cron_job_name:, namespace:)
    handle_k8s_error do
      cron_job = k8s_batch_client.get_cron_job(cron_job_name, namespace)
      cron_job.spec.suspend = false
      k8s_batch_client.update_cron_job(cron_job)
      Rails.logger.info "Resumed CronJob: #{cron_job_name} in namespace: #{namespace}"
    end
  end

  def trigger_job(cron_job_name:, namespace:, job_name: nil)
    handle_k8s_error do
      cron_job = k8s_batch_client.get_cron_job(cron_job_name, namespace)
      job_name ||= "#{cron_job_name}-manual-#{Time.current.to_i}"
      
      # Create a job from the CronJob template
      job_spec = cron_job.spec.jobTemplate.spec.to_h
      job_spec[:metadata] = {
        name: job_name,
        namespace: namespace,
        labels: {
          'managed-by' => 'rails-k8s-controller',
          'cronjob' => cron_job_name,
          'manual-trigger' => 'true'
        }
      }
      
      job = Kubeclient::Resource.new(job_spec)
      k8s_batch_v1_client.create_job(job)
      Rails.logger.info "Triggered manual job: #{job_name} from CronJob: #{cron_job_name} in namespace: #{namespace}"
      
      job_name
    end
  end

  def status(cron_job_name:, namespace:)
    handle_k8s_error do
      cron_job = k8s_batch_client.get_cron_job(cron_job_name, namespace)
      {
        'metadata' => {
          'name' => cron_job.metadata.name,
          'namespace' => cron_job.metadata.namespace,
          'creationTimestamp' => cron_job.metadata.creationTimestamp
        },
        'spec' => {
          'schedule' => cron_job.spec.schedule,
          'suspend' => cron_job.spec.suspend,
          'concurrencyPolicy' => cron_job.spec.concurrencyPolicy
        },
        'status' => {
          'active' => cron_job.status.active&.map(&:to_h),
          'lastScheduleTime' => cron_job.status.lastScheduleTime,
          'lastSuccessfulTime' => cron_job.status.lastSuccessfulTime
        }
      }
    end
  end

  def get_jobs(cron_job_name:, namespace:, limit: 10)
    handle_k8s_error do
      jobs = k8s_batch_v1_client.get_jobs(
        namespace: namespace,
        label_selector: "cronjob=#{cron_job_name}"
      )
      
      # Sort by creation time and limit
      sorted_jobs = jobs.sort_by { |job| job.metadata.creationTimestamp }.reverse.first(limit)
      
      {
        'items' => sorted_jobs.map do |job|
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

  def list(namespace:, label_selector: nil)
    handle_k8s_error do
      options = { namespace: namespace }
      options[:label_selector] = label_selector if label_selector.present?
      
      cron_jobs = k8s_batch_client.get_cron_jobs(options)
      {
        'items' => cron_jobs.map do |cron_job|
          {
            'metadata' => {
              'name' => cron_job.metadata.name,
              'namespace' => cron_job.metadata.namespace,
              'creationTimestamp' => cron_job.metadata.creationTimestamp
            },
            'spec' => {
              'schedule' => cron_job.spec.schedule,
              'suspend' => cron_job.spec.suspend
            },
            'status' => {
              'active' => cron_job.status.active&.size || 0,
              'lastScheduleTime' => cron_job.status.lastScheduleTime
            }
          }
        end
      }
    end
  end

  def exists?(cron_job_name:, namespace:)
    handle_k8s_error do
      k8s_batch_client.get_cron_job(cron_job_name, namespace)
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

  def k8s_batch_v1_client
    @k8s_batch_v1_client ||= Kubeclient::Client.new(
      Rails.application.config.k8s_api_endpoint,
      'batch/v1',
      auth_options: k8s_auth_options,
      ssl_options: k8s_ssl_options
    )
  end
end
