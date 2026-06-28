module Services
  module Tenant
    class TenantProvisioner
      include Dry::Monads[:result]

      def initialize(
        tenant_repository: nil,
        database_provisioner: nil,
        connection_resolver: nil,
        logger: Rails.logger
      )
        @tenant_repository = tenant_repository || Repositories::TenantRepository.new
        @database_provisioner = database_provisioner || Services::Database::DatabaseProvisioner.new
        @connection_resolver = connection_resolver || DatabaseSwitcher::ConnectionResolver.new
        @logger = logger
      end

      # @param slug [String]
      # @param name [String]
      # @param plan [String]
      # @param settings [Hash]
      # @return [Dry::Monads::Result]
      def provision(slug:, name:, plan:, settings: {})
        return Failure(Domain::Shared::Errors::ConflictError.new("Slug already taken: #{slug}")) if slug_taken?(slug)

        tenant = Domain::Tenant::Tenant.create(
          slug: slug,
          name: name,
          plan: plan,
          settings: settings
        )

        saved_tenant = @tenant_repository.save(tenant)
        @logger.info("Tenant created: #{saved_tenant.slug} (#{saved_tenant.id})")

        database_config = @connection_resolver.build_config_for_provisioning(saved_tenant)
        provisioning_result = @database_provisioner.provision(saved_tenant, database_config)

        case provisioning_result
        in Success(config)
          tenanted = saved_tenant.assign_database_config(config).activate
          final_tenant = @tenant_repository.save(tenanted)
          @logger.info("Tenant provisioned successfully: #{final_tenant.slug}")
          Success(final_tenant)
        in Failure(error)
          @logger.error("Database provisioning failed for #{saved_tenant.slug}: #{error.message}")
          Failure(Domain::Shared::Errors::TenantProvisioningError.new(
            "Database provisioning failed: #{error.message}"
          ))
        end
      rescue Domain::Shared::Errors::ValidationError => e
        Failure(e)
      rescue StandardError => e
        @logger.error("Unexpected error provisioning tenant #{slug}: #{e.class} - #{e.message}")
        Failure(Domain::Shared::Errors::TenantProvisioningError.new(e.message))
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @param reason [String, nil]
      # @return [Dry::Monads::Result]
      def suspend(tenant, reason: nil)
        suspended_tenant = tenant.suspend(reason: reason)
        saved = @tenant_repository.save(suspended_tenant)
        @logger.info("Tenant suspended: #{saved.slug}")
        Success(saved)
      rescue Domain::Shared::Errors::InvalidStateTransitionError => e
        Failure(e)
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Dry::Monads::Result]
      def activate(tenant)
        activated = tenant.activate
        saved = @tenant_repository.save(activated)
        @logger.info("Tenant activated: #{saved.slug}")
        Success(saved)
      rescue Domain::Shared::Errors::InvalidStateTransitionError => e
        Failure(e)
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Dry::Monads::Result]
      def terminate(tenant)
        terminated_tenant = tenant.terminate
        saved = @tenant_repository.save(terminated_tenant)

        @database_provisioner.deprovision(tenant) if tenant.database_provisioned?

        @logger.info("Tenant terminated: #{saved.slug}")
        Success(saved)
      rescue Domain::Shared::Errors::InvalidStateTransitionError => e
        Failure(e)
      rescue StandardError => e
        Failure(Domain::Shared::Errors::TenantProvisioningError.new(e.message))
      end

      private

      def slug_taken?(slug)
        @tenant_repository.exists_by_slug?(slug)
      end
    end
  end
end
