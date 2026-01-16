# config/initializers/sidekiq.rb

# タイムゾーン設定
ENV['TZ'] = 'Asia/Tokyo'

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
  
  # sidekiq-schedulerの設定
  config.on(:startup) do
    Rails.logger.info("=== Sidekiq Scheduler Startup ===")
    
    # Sidekiq.scheduleを初期化（nilにならないように）
    Sidekiq.schedule ||= {}
    
    # Redisから動的スケジュールを読み込み
    dynamic_schedules = load_dynamic_schedules
    
    # 既存のスケジュール（YAMLから読み込まれたもの）とマージ
    if Sidekiq.schedule.is_a?(Hash)
      Sidekiq.schedule.merge!(dynamic_schedules)
    else
      Sidekiq.schedule = dynamic_schedules
    end
    
    Rails.logger.info("Total schedules loaded: #{Sidekiq.schedule.size}")
    Sidekiq.schedule.each do |name, config|
      Rails.logger.info("  - #{name}: #{config['class']} (#{config['cron'] || config['at']})")
    end
    
    # スケジューラーを開始
    if Sidekiq.server?
      require 'sidekiq-scheduler'
      Sidekiq::Scheduler.enabled = true
      
      # 定期的にスケジュール変更をチェック（60秒ごと）
      Thread.new do
        last_check = Time.now.to_i
        Rails.logger.info("Schedule watcher thread started")
        
        loop do
          sleep 60
          begin
            changed_at = Sidekiq.redis { |c| c.get('schedules:changed')&.to_i || 0 }
            if changed_at > last_check
              Rails.logger.info("Schedule change detected at #{Time.at(changed_at)}, reloading...")
              
              # 動的スケジュールを再読み込み
              new_dynamic_schedules = load_dynamic_schedules
              
              # 既存のスケジュールとマージ
              yaml_schedules = load_yaml_schedules
              all_schedules = yaml_schedules.merge(new_dynamic_schedules)
              
              Sidekiq.schedule = all_schedules
              Sidekiq::Scheduler.reload_schedule!
              
              Rails.logger.info("Reloaded #{all_schedules.size} schedules")
              last_check = Time.now.to_i
            end
          rescue => e
            Rails.logger.error("Schedule check failed: #{e.message}")
            Rails.logger.error(e.backtrace.join("\n"))
          end
        end
      end
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

# ActiveJobの設定
ActiveJob::Base.queue_adapter = :sidekiq

# Rails 8対応: Solid Queueを使わずSidekiqを使う場合
Rails.application.config.active_job.queue_adapter = :sidekiq

# YAMLファイルからスケジュール読み込み
def load_yaml_schedules
  yaml_file = Rails.root.join('config', 'sidekiq.yml')
  return {} unless File.exist?(yaml_file)
  
  begin
    config = YAML.load_file(yaml_file)
    # sidekiq-scheduler 5.0+ では :scheduler: :schedule: の下にある
    yaml_schedules = config.dig(:scheduler, :schedule) || 
                     config.dig('scheduler', 'schedule') ||
                     {}
    Rails.logger.info("Loaded #{yaml_schedules.size} schedules from YAML")
    yaml_schedules
  rescue => e
    Rails.logger.error("Failed to load schedules from YAML: #{e.message}")
    {}
  end
end

# Redisから動的スケジュール読み込み
def load_dynamic_schedules
  schedules = {}
  
  begin
    Sidekiq.redis do |conn|
      all_schedules = conn.hgetall('schedules')
      all_schedules.each do |name, config_json|
        schedules[name] = JSON.parse(config_json)
      end
    end
    Rails.logger.info("Loaded #{schedules.size} dynamic schedules from Redis")
  rescue => e
    Rails.logger.error("Failed to load schedules from Redis: #{e.message}")
  end
  
  # 常に空のハッシュでも返す（nilにしない）
  schedules
end
