module Helpers
  module DatabaseHelpers
    def stub_database_provisioner(success: true, config: nil)
      provisioner = instance_double(Services::Database::DatabaseProvisioner)
      allow(Services::Database::DatabaseProvisioner).to receive(:new).and_return(provisioner)

      if success
        resolved_config = config || Domain::Tenant::DatabaseConfig.for_aws(
          tenant_slug: "test-tenant",
          rds_host: "localhost"
        )
        allow(provisioner).to receive(:provision).and_return(Success(resolved_config))
        allow(provisioner).to receive(:deprovision).and_return(Success(true))
      else
        allow(provisioner).to receive(:provision).and_return(
          Failure(Domain::Shared::Errors::TenantProvisioningError.new("Provisioning failed"))
        )
        allow(provisioner).to receive(:deprovision).and_return(
          Failure(Domain::Shared::Errors::TenantProvisioningError.new("Deprovision failed"))
        )
      end

      provisioner
    end

    def stub_connection_manager
      manager = instance_double(DatabaseSwitcher::ConnectionManager)
      allow(DatabaseSwitcher::ConnectionManager).to receive(:new).and_return(manager)
      allow(manager).to receive(:with_tenant).and_yield
      manager
    end

    def stub_pool_registry
      registry = instance_double(DatabaseSwitcher::ConnectionPoolRegistry)
      allow(DatabaseSwitcher::ConnectionPoolRegistry).to receive(:instance).and_return(registry)
      pool = instance_double(ConnectionPool)
      allow(registry).to receive(:fetch_or_create).and_return(pool)
      allow(pool).to receive(:with_connection).and_yield(ActiveRecord::Base.connection)
      registry
    end
  end
end
