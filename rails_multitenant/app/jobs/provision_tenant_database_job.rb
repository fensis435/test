class ProvisionTenantDatabaseJob < ApplicationJob
  queue_as :provisioning
  sidekiq_options retry: 3, backtrace: true

  def perform(tenant_id)
    tenant_repository = Repositories::TenantRepository.new
    tenant = tenant_repository.find_by_id(tenant_id)

    unless tenant
      Rails.logger.error("ProvisionTenantDatabaseJob: Tenant not found #{tenant_id}")
      return
    end

    if tenant.database_provisioned?
      Rails.logger.info("ProvisionTenantDatabaseJob: Already provisioned #{tenant.slug}")
      return
    end

    provisioner = Services::Tenant::TenantProvisioner.new(tenant_repository: tenant_repository)
    resolver = DatabaseSwitcher::ConnectionResolver.new
    db_config = resolver.build_config_for_provisioning(tenant)

    db_provisioner = Services::Database::DatabaseProvisioner.new
    result = db_provisioner.provision(tenant, db_config)

    case result
    in Dry::Monads::Success(config)
      tenanted = tenant.assign_database_config(config).activate
      tenant_repository.save(tenanted)
      Rails.logger.info("ProvisionTenantDatabaseJob: Completed for #{tenant.slug}")
    in Dry::Monads::Failure(error)
      Rails.logger.error("ProvisionTenantDatabaseJob: Failed for #{tenant.slug}: #{error.message}")
      raise error.message
    end
  end
end
