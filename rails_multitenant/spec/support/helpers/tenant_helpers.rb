module Helpers
  module TenantHelpers
    def create_domain_tenant(slug: "test-tenant", name: "Test Tenant", plan: "professional", status: "active")
      db_config = Domain::Tenant::DatabaseConfig.for_aws(
        tenant_slug: slug,
        rds_host: "localhost"
      )

      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid,
        slug: slug,
        name: name,
        status: status,
        plan: plan,
        settings: {},
        database_config: status == "active" ? db_config : nil,
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    def set_current_tenant(tenant)
      TenantResolver::TenantContext.set(tenant: tenant)
    end

    def with_tenant_context(tenant, &block)
      TenantResolver::TenantContext.with_tenant(tenant, &block)
    end

    def stub_tenant_resolution(tenant)
      resolver = instance_double(TenantResolver::Resolver)
      allow(TenantResolver::Resolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:resolve).and_return(tenant)
      resolver
    end
  end
end
