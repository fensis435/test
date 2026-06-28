module DatabaseSwitcher
  class ConnectionResolver
    def initialize(platform: nil)
      @platform = platform || Rails.application.config.x.database.platform
    end

    # @param tenant [Domain::Tenant::Tenant]
    # @return [Domain::Tenant::DatabaseConfig]
    def resolve(tenant)
      unless tenant.database_provisioned?
        raise Domain::Shared::Errors::DatabaseConnectionError,
              "Tenant #{tenant.slug} has no database configuration"
      end

      tenant.database_config
    end

    # Build a new config for provisioning (before database exists)
    # @param tenant [Domain::Tenant::Tenant]
    # @return [Domain::Tenant::DatabaseConfig]
    def build_config_for_provisioning(tenant)
      case @platform
      when "aws"
        build_aws_config(tenant)
      when "onprem"
        build_onprem_config(tenant)
      else
        raise Domain::Shared::Errors::DatabaseConnectionError,
              "Unknown platform: #{@platform}"
      end
    end

    private

    def build_aws_config(tenant)
      rds_host = ENV.fetch("RDS_HOST") do
        raise Domain::Shared::Errors::DatabaseConnectionError, "RDS_HOST not configured"
      end

      Domain::Tenant::DatabaseConfig.for_aws(
        tenant_slug: tenant.slug,
        rds_host: rds_host,
        rds_port: ENV.fetch("RDS_PORT", 5432).to_i
      )
    end

    def build_onprem_config(tenant)
      namespace = Rails.application.config.x.database.onprem_namespace

      Domain::Tenant::DatabaseConfig.for_onprem(
        tenant_slug: tenant.slug,
        namespace: namespace
      )
    end
  end
end
