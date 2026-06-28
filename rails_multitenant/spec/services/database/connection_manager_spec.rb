require "rails_helper"

RSpec.describe DatabaseSwitcher::ConnectionManager do
  subject(:manager) do
    described_class.new(
      connection_resolver: connection_resolver,
      pool_registry: pool_registry
    )
  end

  let(:connection_resolver) { instance_double(DatabaseSwitcher::ConnectionResolver) }
  let(:pool_registry) { instance_double(DatabaseSwitcher::ConnectionPoolRegistry) }
  let(:pool) { instance_double(ConnectionPool) }
  let(:mock_connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }

  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
  end

  let(:active_tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "active",
      plan: "professional",
      database_config: db_config,
      created_at: 2.hours.ago,
      updated_at: 1.hour.ago
    )
  end

  before do
    allow(connection_resolver).to receive(:resolve).with(active_tenant).and_return(db_config)
    allow(pool_registry).to receive(:fetch_or_create).and_return(pool)
    allow(pool).to receive(:with_connection).and_yield(mock_connection)
    allow(mock_connection).to receive(:schema_search_path=)
    allow(mock_connection).to receive(:schema_search_path).and_return("public")
    allow(ActiveRecord::Base).to receive(:connection_handler).and_return(
      instance_double(ActiveRecord::ConnectionAdapters::ConnectionHandler,
                      while_preventing_writes: nil)
    )
    allow(ActiveRecord::Base).to receive(:connection_pool).and_return(
      instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool, with_connection: nil)
    )
  end

  describe "#with_tenant" do
    it "requires a block" do
      expect { manager.with_tenant(active_tenant) }.to raise_error(ArgumentError, /Block required/)
    end

    context "when tenant is suspended" do
      let(:suspended_tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "susp", name: "Susp",
          status: "suspended", plan: "free",
          database_config: db_config,
          created_at: 2.hours.ago, updated_at: 1.hour.ago,
          suspended_at: 1.hour.ago
        )
      end

      it "raises TenantSuspendedError" do
        expect { manager.with_tenant(suspended_tenant) { } }
          .to raise_error(Domain::Shared::Errors::TenantSuspendedError)
      end
    end

    context "when tenant has no database config" do
      let(:unprovisioned_tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "new-t", name: "New",
          status: "active", plan: "free",
          database_config: nil,
          created_at: 1.hour.ago, updated_at: 1.hour.ago
        )
      end

      it "raises TenantProvisioningError" do
        expect { manager.with_tenant(unprovisioned_tenant) { } }
          .to raise_error(Domain::Shared::Errors::TenantProvisioningError)
      end
    end

    context "when platform is aws" do
      before do
        allow(Rails.application.config.x.database).to receive(:platform).and_return("aws")
      end

      it "fetches pool from registry" do
        allow(ActiveRecord::Base.connection_handler).to receive(:while_preventing_writes).and_yield
        allow(ActiveRecord::Base.connection_pool).to receive(:with_connection).and_yield(mock_connection)
        manager.with_tenant(active_tenant) { "result" }
        expect(pool_registry).to have_received(:fetch_or_create).with(db_config)
      end
    end
  end

  describe "#with_system" do
    it "requires a block" do
      expect { manager.with_system }.to raise_error(ArgumentError, /Block required/)
    end

    it "yields and restores schema" do
      current_conn = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
      allow(ActiveRecord::Base).to receive(:connection).and_return(current_conn)
      allow(current_conn).to receive(:schema_search_path).and_return("tenant_acme_corp")
      allow(current_conn).to receive(:schema_search_path=)

      result = manager.with_system { "system_result" }
      expect(result).to eq("system_result")
    end
  end
end
