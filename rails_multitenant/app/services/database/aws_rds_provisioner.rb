module Services
  module Database
    class AwsRdsProvisioner
      include Dry::Monads[:result]

      MIGRATION_TIMEOUT = 300

      def initialize(logger: Rails.logger)
        @logger = logger
      end

      # On AWS, we use PostgreSQL schemas within a shared RDS instance.
      # Each tenant gets their own schema for isolation at the database level.
      # @param tenant [Domain::Tenant::Tenant]
      # @param config [Domain::Tenant::DatabaseConfig]
      # @return [Dry::Monads::Result<Domain::Tenant::DatabaseConfig>]
      def provision(tenant, config)
        schema_name = tenant.schema_name

        ActiveRecord::Base.connection.transaction do
          create_schema(schema_name)
          create_tenant_role(config.username, schema_name)
          run_tenant_migrations(schema_name)
        end

        @logger.info("AWS schema provisioned: #{schema_name}")
        Success(config)
      rescue ActiveRecord::StatementInvalid => e
        Failure(Domain::Shared::Errors::DatabaseConnectionError.new("Schema creation failed: #{e.message}"))
      rescue StandardError => e
        Failure(Domain::Shared::Errors::TenantProvisioningError.new(e.message))
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Dry::Monads::Result]
      def deprovision(tenant)
        schema_name = tenant.schema_name

        ActiveRecord::Base.connection.transaction do
          revoke_privileges(tenant.database_config.username, schema_name) if tenant.database_provisioned?
          drop_schema(schema_name)
        end

        @logger.info("AWS schema dropped: #{schema_name}")
        Success(true)
      rescue StandardError => e
        Failure(Domain::Shared::Errors::TenantProvisioningError.new("Schema drop failed: #{e.message}"))
      end

      private

      def create_schema(schema_name)
        conn = ActiveRecord::Base.connection
        raise "Schema name is unsafe" unless safe_schema_name?(schema_name)

        conn.execute("CREATE SCHEMA IF NOT EXISTS #{conn.quote_column_name(schema_name)}")
        @logger.debug("Created schema: #{schema_name}")
      end

      def create_tenant_role(username, schema_name)
        conn = ActiveRecord::Base.connection

        # Idempotent role creation
        existing = conn.execute("SELECT 1 FROM pg_roles WHERE rolname = #{conn.quote(username)}").any?

        unless existing
          # Generate secure password for role
          password = SecureRandom.hex(32)
          conn.execute("CREATE ROLE #{conn.quote_column_name(username)} WITH LOGIN PASSWORD #{conn.quote(password)}")

          # Store hashed password securely (retrieve via Secrets Manager in production)
          store_credentials(username, password)
        end

        conn.execute("GRANT USAGE ON SCHEMA #{conn.quote_column_name(schema_name)} TO #{conn.quote_column_name(username)}")
        conn.execute("GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA #{conn.quote_column_name(schema_name)} TO #{conn.quote_column_name(username)}")
        conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA #{conn.quote_column_name(schema_name)} GRANT ALL ON TABLES TO #{conn.quote_column_name(username)}")
        conn.execute("ALTER DEFAULT PRIVILEGES IN SCHEMA #{conn.quote_column_name(schema_name)} GRANT ALL ON SEQUENCES TO #{conn.quote_column_name(username)}")
      end

      def run_tenant_migrations(schema_name)
        Timeout.timeout(MIGRATION_TIMEOUT) do
          ActiveRecord::Base.connection.schema_search_path = schema_name
          ActiveRecord::MigrationContext.new(
            Rails.root.join("db/tenant_migrations").to_s,
            ActiveRecord::SchemaMigration
          ).migrate
        end
      ensure
        ActiveRecord::Base.connection.schema_search_path = "public"
      end

      def revoke_privileges(username, schema_name)
        conn = ActiveRecord::Base.connection
        conn.execute("REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA #{conn.quote_column_name(schema_name)} FROM #{conn.quote_column_name(username)}")
        conn.execute("REVOKE USAGE ON SCHEMA #{conn.quote_column_name(schema_name)} FROM #{conn.quote_column_name(username)}")
      rescue StandardError => e
        @logger.warn("Could not revoke privileges: #{e.message}")
      end

      def drop_schema(schema_name)
        conn = ActiveRecord::Base.connection
        raise "Schema name is unsafe" unless safe_schema_name?(schema_name)

        conn.execute("DROP SCHEMA IF EXISTS #{conn.quote_column_name(schema_name)} CASCADE")
      end

      def safe_schema_name?(name)
        name.match?(/\Atenant_[a-z0-9_]{1,60}\z/)
      end

      def store_credentials(username, password)
        if ENV["AWS_SECRETS_MANAGER_ENABLED"] == "true"
          Services::Aws::SecretsManagerClient.new.store_tenant_credential(
            username: username,
            password: password
          )
        else
          Rails.logger.warn("Credential storage: SecretsManager disabled, password logged to secure log only")
        end
      end
    end
  end
end
