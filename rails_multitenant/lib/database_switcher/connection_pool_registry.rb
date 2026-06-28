module DatabaseSwitcher
  class ConnectionPoolRegistry
    include Singleton

    MAX_POOLS = 1200
    POOL_EVICTION_TTL = 30.minutes
    CLEANUP_INTERVAL = 5.minutes

    def initialize
      @pools = {}
      @pool_last_used = {}
      @mutex = Mutex.new
      schedule_cleanup
    end

    # @param config [Domain::Tenant::DatabaseConfig]
    # @return [ConnectionPool::Wrapper]
    def fetch_or_create(config)
      cache_key = build_cache_key(config)

      @mutex.synchronize do
        evict_stale_pools! if @pools.size >= MAX_POOLS

        unless @pools.key?(cache_key)
          @pools[cache_key] = build_pool(config)
        end

        @pool_last_used[cache_key] = Time.current
        @pools[cache_key]
      end
    end

    # Remove pool for a specific tenant (e.g., on termination)
    # @param config [Domain::Tenant::DatabaseConfig]
    def invalidate(config)
      cache_key = build_cache_key(config)

      @mutex.synchronize do
        pool = @pools.delete(cache_key)
        @pool_last_used.delete(cache_key)
        pool&.shutdown { |conn| conn.disconnect! }
      end
    end

    def pool_count
      @mutex.synchronize { @pools.size }
    end

    def stats
      @mutex.synchronize do
        {
          total_pools: @pools.size,
          pool_keys: @pools.keys.map { |k| k.split(":").first }
        }
      end
    end

    private

    def build_pool(config)
      db_config = build_ar_config(config)

      ConnectionPool.new(size: config.pool_size, timeout: 5) do
        conn = ActiveRecord::Base.establish_connection(db_config).connection
        conn.verify!
        conn
      end
    end

    def build_ar_config(config)
      password = fetch_password(config)
      {
        adapter: "postgresql",
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        password: password,
        pool: config.pool_size,
        checkout_timeout: 5,
        connect_timeout: 5,
        sslmode: config.ssl_mode,
        prepared_statements: false,
        advisory_locks: false,
        variables: {
          statement_timeout: 10_000,
          lock_timeout: 5_000
        }
      }
    end

    def fetch_password(config)
      if config.aws? && ENV["USE_IAM_AUTH"] == "true"
        Services::Database::RdsIamAuthenticator.new.generate_token(
          host: config.host,
          port: config.port,
          username: config.username,
          region: ENV.fetch("AWS_REGION", "ap-northeast-1")
        )
      else
        ENV.fetch("TENANT_DB_PASSWORD_#{config.database.upcase}", ENV["DEFAULT_TENANT_DB_PASSWORD"])
      end
    end

    def build_cache_key(config)
      "#{config.host}:#{config.port}:#{config.database}:#{config.username}"
    end

    def evict_stale_pools!
      cutoff = Time.current - POOL_EVICTION_TTL
      stale_keys = @pool_last_used.select { |_, used_at| used_at < cutoff }.keys

      stale_keys.each do |key|
        pool = @pools.delete(key)
        @pool_last_used.delete(key)
        pool&.shutdown { |conn| conn.disconnect! rescue nil }
      end

      Rails.logger.info("Evicted #{stale_keys.size} stale tenant connection pools")
    end

    def schedule_cleanup
      Thread.new do
        loop do
          sleep(CLEANUP_INTERVAL)
          @mutex.synchronize { evict_stale_pools! }
        rescue StandardError => e
          Rails.logger.error("Pool cleanup error: #{e.message}")
        end
      end
    end
  end
end
