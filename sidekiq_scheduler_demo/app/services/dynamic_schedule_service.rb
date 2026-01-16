# app/services/dynamic_schedule_service.rb
class DynamicScheduleService
  class << self
    # 特定の日時にジョブをスケジュール登録
    # @param job_name [String] ユニークなジョブ識別名
    # @param job_class [String] ActiveJobクラス名（例: 'MyNotificationJob'）
    # @param scheduled_at [Time/DateTime/String] 実行日時（Asia/Tokyo）
    # @param args [Array] ジョブに渡す引数
    # @param queue [String] キュー名（デフォルト: 'default'）
    def register(job_name:, job_class:, scheduled_at:, args: [], queue: 'default')
      # 日時をAsia/Tokyoのタイムゾーンで解釈
      scheduled_time = parse_time_in_jst(scheduled_at)
      
      # 過去の時刻チェック
      if scheduled_time < Time.current
        raise ArgumentError, "scheduled_at must be in the future: #{scheduled_time}"
      end
      
      # スケジュール設定を作成
      schedule_config = {
        'class' => job_class,
        'args' => args,
        'queue' => queue,
        'at' => scheduled_time.iso8601,
        'enabled' => true
      }
      
      # Redisに保存
      Sidekiq.redis do |conn|
        conn.hset('schedules', job_name, schedule_config.to_json)
        # スケジュール変更を通知（タイムスタンプを更新）
        conn.set('schedules:changed', Time.now.to_i)
      end
      
      # Sidekiqワーカーに再読み込みを指示（非同期）
      notify_schedule_change
      
      {
        job_name: job_name,
        job_class: job_class,
        scheduled_at: scheduled_time.in_time_zone('Asia/Tokyo').strftime('%Y-%m-%d %H:%M:%S %Z'),
        status: 'registered'
      }
    end
    
    # cron形式で繰り返しジョブを登録（JST対応）
    # @param job_name [String] ユニークなジョブ識別名
    # @param job_class [String] ActiveJobクラス名
    # @param cron [String] cron式（例: '0 9 * * *' = 毎日9:00）
    # @param args [Array] ジョブに渡す引数
    def register_recurring(job_name:, job_class:, cron:, args: [], queue: 'default')
      schedule_config = {
        'class' => job_class,
        'cron' => cron,
        'args' => args,
        'queue' => queue,
        'enabled' => true
      }
      
      Sidekiq.redis do |conn|
        conn.hset('schedules', job_name, schedule_config.to_json)
        conn.set('schedules:changed', Time.now.to_i)
      end
      
      notify_schedule_change
      
      {
        job_name: job_name,
        job_class: job_class,
        cron: cron,
        status: 'registered'
      }
    end
    
    # スケジュールされたジョブを削除
    def unregister(job_name:)
      Sidekiq.redis do |conn|
        conn.hdel('schedules', job_name)
        conn.set('schedules:changed', Time.now.to_i)
      end
      
      notify_schedule_change
      
      { job_name: job_name, status: 'unregistered' }
    end
    
    # 登録済みスケジュール一覧
    def list
      schedules = load_schedules
      schedules.map do |name, config|
        {
          name: name,
          class: config['class'],
          at: config['at'],
          cron: config['cron'],
          queue: config['queue'],
          enabled: config['enabled']
        }
      end
    end
    
    # 特定のスケジュールを取得
    def get(job_name:)
      schedule = load_schedules[job_name]
      return nil unless schedule
      
      {
        name: job_name,
        class: schedule['class'],
        at: schedule['at'],
        cron: schedule['cron'],
        args: schedule['args'],
        queue: schedule['queue'],
        enabled: schedule['enabled']
      }
    end
    
    private
    
    # Sidekiqワーカーにスケジュール変更を通知
    def notify_schedule_change
      # スケジュールリロード用のジョブをキューに投入
      ScheduleReloaderJob.perform_async if defined?(ScheduleReloaderJob)
    rescue => e
      Rails.logger.warn("Failed to notify schedule change: #{e.message}")
    end
    
    # Redisからスケジュールを読み込み
    def load_schedules
      schedules = {}
      Sidekiq.redis do |conn|
        all_schedules = conn.hgetall('schedules')
        all_schedules.each do |name, config_json|
          schedules[name] = JSON.parse(config_json)
        end
      end
      
      # YAMLファイルのスケジュールもマージ（もしあれば）
      yaml_schedules = load_yaml_schedules
      schedules.merge(yaml_schedules)
    end
    
    # YAMLファイルからスケジュール読み込み
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
    
    # 日時文字列をJSTとして解釈
    def parse_time_in_jst(time_input)
      case time_input
      when Time, DateTime, ActiveSupport::TimeWithZone
        time_input.in_time_zone('Asia/Tokyo')
      when String
        # 文字列をJSTとして解釈
        Time.zone = 'Asia/Tokyo'
        Time.zone.parse(time_input)
      else
        raise ArgumentError, "Invalid time format: #{time_input}"
      end
    end
  end
end
