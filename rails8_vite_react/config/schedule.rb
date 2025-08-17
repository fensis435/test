every 1.day, at: '3:00 am' do
  rake 'auth:cleanup'
end

every 5.minutes do
  runner "SessionTimeoutMonitorJob.perform_later"
end

every 1.day, at: '3:00 am' do
  runner "K8s::MaintenanceService.new.cleanup_orphaned_resources"
end
