# app/jobs/schedule_reloader_job.rb
# Sidekiqワーカープロセス内でスケジュールをリロードするジョブ
class ScheduleReloaderJob
  include Sidekiq::Job
  
  # 注意: このジョブはActiveJobではなく、Sidekiq::Jobを直接使用
  # 理由: ActiveJobのキューシステムを経由せず、直接Sidekiqワーカーで実行させるため
  
  def perform
    # Redisから最新のスケジュールを読み込み
    schedules = load_schedules_from_redis
    
    # Sidekiq.scheduleを更新
    Sidekiq.schedule = schedules
    
    # スケジューラーをリロード（このプロセス内で実行されるので有効）
    if Sidekiq.server?
      Sidekiq::Scheduler.reload_schedule!
      Rails.logger.info("Schedule reloaded successfully: #{schedules.keys.join(', ')}")
    end
  rescue => e
    Rails.logger.error("Failed to reload schedule: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end
  
  private
  
  def load_schedules_from_redis
    schedules = {}
    Sidekiq.redis do |conn|
      all_schedules = conn.hgetall('schedules')
      all_schedules.each do |name, config_json|
        schedules[name] = JSON.parse(config_json)
      end
    end
    
    # YAMLファイルのスケジュールもマージ
    yaml_schedules = load_yaml_schedules
    schedules.merge(yaml_schedules)
  end
  
  def load_yaml_schedules
    yaml_file = Rails.root.join('config', 'sidekiq.yml')
    return {} unless File.exist?(yaml_file)
    
    config = YAML.load_file(yaml_file)
    # sidekiq-scheduler 5.0+ では :scheduler: :schedule: の下にある
    config.dig(:scheduler, :schedule) || 
    config.dig('scheduler', 'schedule') ||
    config[:schedule] || 
    config['schedule'] || 
    {}
  rescue => e
    Rails.logger.error("Failed to load YAML schedules: #{e.message}")
    {}
  end
end
