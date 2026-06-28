module Services
  module Database
    class DatabaseProvisioner
      include Dry::Monads[:result]

      def initialize(
        platform: nil,
        aws_provisioner: nil,
        onprem_provisioner: nil,
        logger: Rails.logger
      )
        @platform = platform || Rails.application.config.x.database.platform
        @aws_provisioner = aws_provisioner || AwsRdsProvisioner.new
        @onprem_provisioner = onprem_provisioner || OnpremPostgresProvisioner.new
        @logger = logger
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @param config [Domain::Tenant::DatabaseConfig]
      # @return [Dry::Monads::Result<Domain::Tenant::DatabaseConfig>]
      def provision(tenant, config)
        @logger.info("Provisioning database for tenant #{tenant.slug} on platform #{@platform}")

        result = case @platform
                 when "aws"
                   @aws_provisioner.provision(tenant, config)
                 when "onprem"
                   @onprem_provisioner.provision(tenant, config)
                 else
                   Failure(Domain::Shared::Errors::DatabaseConnectionError.new("Unknown platform: #{@platform}"))
                 end

        log_result(tenant, result)
        result
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Dry::Monads::Result]
      def deprovision(tenant)
        @logger.info("Deprovisioning database for tenant #{tenant.slug}")

        case @platform
        when "aws"
          @aws_provisioner.deprovision(tenant)
        when "onprem"
          @onprem_provisioner.deprovision(tenant)
        else
          Failure(Domain::Shared::Errors::DatabaseConnectionError.new("Unknown platform: #{@platform}"))
        end
      end

      private

      def log_result(tenant, result)
        case result
        in Success
          @logger.info("Database provisioned for tenant #{tenant.slug}")
        in Failure(error)
          @logger.error("Database provisioning failed for #{tenant.slug}: #{error.message}")
        end
      end
    end
  end
end
