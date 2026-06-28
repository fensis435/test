module DatabaseSwitcher
  class ConnectionManager
    include Dry::Monads[:result]

    SYSTEM_SCHEMAS = %w[public information_schema pg_catalog pg_toast].freeze

    def initialize(
      connection_resolver: nil,
      pool_registry: nil,
      logger: Rails.logger
    )
      @connection_resolver = connection_resolver || ConnectionResolver.new
      @pool_registry = pool_registry || ConnectionPoolRegistry.instance
      @logger = logger
    end

    # Switch to tenant database/schema and execute block
    # @param tenant [Domain::Tenant::Tenant]
    # @yield block to execute within tenant context
    # @return [Object] result of block
    def with_tenant(tenant, &block)
      raise ArgumentError, "Block required" unless block_given?
      raise Domain::Shared::Errors::TenantSuspendedError, tenant.slug if tenant.suspended?
      raise Domain::Shared::Errors::TenantProvisioningError, "Database not provisioned" unless tenant.database_provisioned?

      config = @connection_resolver.resolve(tenant)
      switch_connection(config, tenant.schema_name, &block)
    rescue ActiveRecord::StatementInvalid => e
      raise Domain::Shared::Errors::DatabaseConnectionError, "Database error: #{e.message}"
    end

    # Switch to public/system schema
    # @yield block to execute in system context
    def with_system(&block)
      raise ArgumentError, "Block required" unless block_given?

      previous = current_schema
      switch_to_schema("public", &block)
    ensure
      restore_schema(previous)
    end

    # Get current schema name
    def current_schema
      ActiveRecord::Base.connection.schema_search_path
    rescue ActiveRecord::ConnectionNotEstablished
      "public"
    end

    # Check if currently within a tenant context
    def in_tenant_context?
      schema = current_schema
      schema.present? && !SYSTEM_SCHEMAS.include?(schema.delete('"').strip)
    end

    private

    def switch_connection(config, schema_name, &block)
      if Rails.application.config.x.database.platform == "aws"
        switch_aws_connection(config, schema_name, &block)
      else
        switch_onprem_connection(config, schema_name, &block)
      end
    end

    def switch_aws_connection(config, schema_name, &block)
      # AWS: Use schema-based isolation on RDS (PostgreSQL schema per tenant)
      pool = @pool_registry.fetch_or_create(config)
      pool.with_connection do |conn|
        ActiveRecord::Base.connection_handler.while_preventing_writes(false) do
          previous_path = conn.schema_search_path
          begin
            conn.schema_search_path = schema_name
            ActiveRecord::Base.connection_pool.with_connection do
              yield conn
            end
          ensure
            conn.schema_search_path = previous_path rescue nil
          end
        end
      end
    end

    def switch_onprem_connection(config, schema_name, &block)
      # On-prem: Each tenant has its own PostgreSQL pod (database-per-tenant)
      pool = @pool_registry.fetch_or_create(config)
      pool.with_connection do |conn|
        yield conn
      end
    end

    def switch_to_schema(schema_name)
      current = ActiveRecord::Base.connection.schema_search_path
      ActiveRecord::Base.connection.schema_search_path = schema_name
      yield
    ensure
      ActiveRecord::Base.connection.schema_search_path = current rescue nil
    end

    def restore_schema(schema)
      ActiveRecord::Base.connection.schema_search_path = schema if schema
    rescue StandardError => e
      @logger.error("Failed to restore schema: #{e.message}")
    end
  end
end
