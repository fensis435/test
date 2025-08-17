# StatefulSet
stateful_set_service = K8s::StatefulSetService.new
stateful_set_service.scale(stateful_set_name: 'my-db', namespace: 'default', replicas: 3)
stateful_set_service.wait_for_rollout(stateful_set_name: 'my-db', namespace: 'default')

# Job
job_service = K8s::JobService.new
job_service.create(
  job_name: 'data-migration', 
  namespace: 'default', 
  image: 'my-app:latest',
  command: ['rake'], 
  args: ['db:migrate']
)
result = job_service.wait_for_completion(job_name: 'data-migration', namespace: 'default')

# CronJob
cron_job_service = K8s::CronJobService.new
cron_job_service.create(
  cron_job_name: 'backup-job',
  namespace: 'default',
  schedule: '0 2 * * *',
  image: 'backup-tool:latest'
)
cron_job_service.trigger_job(cron_job_name: 'backup-job', namespace: 'default')
