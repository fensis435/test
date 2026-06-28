require "rails_helper"

RSpec.describe Services::Database::AwsRdsProvisioner do
  subject(:provisioner) { described_class.new(logger: logger) }

  let(:logger) { instance_double(ActiveSupport::Logger, info: nil, debug: nil, warn: nil, error: nil) }

  let(:tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "provisioning",
      plan: "professional",
      created_at: 1.hour.ago,
      updated_at: 1.hour.ago
    )
  end

  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
  end

  let(:mock_connection) do
    instance_double(
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter,
      execute: double("result", any?: false),
      quote: "'quoted'",
      quote_column_name: '"quoted_column"',
      schema_search_path: "public",
      "schema_search_path=": nil,
      transaction: nil
    )
  end

  before do
    allow(ActiveRecord::Base).to receive(:connection).and_return(mock_connection)
    allow(mock_connection).to receive(:transaction).and_yield
    allow(mock_connection).to receive(:execute).and_return(double("result", any?: false))
    allow(mock_connection).to receive(:quote) { |v| "'#{v}'" }
    allow(mock_connection).to receive(:quote_column_name) { |v| "\"#{v}\"" }

    migration_context = instance_double(ActiveRecord::MigrationContext)
    allow(ActiveRecord::MigrationContext).to receive(:new).and_return(migration_context)
    allow(migration_context).to receive(:migrate)

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("AWS_SECRETS_MANAGER_ENABLED", anything).and_return("false")
    allow(ENV).to receive(:[]).with("AWS_SECRETS_MANAGER_ENABLED").and_return("false")
  end

  describe "#provision" do
    context "when provisioning succeeds" do
      it "returns Success with the database config" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_success
        expect(result.value!).to eq(db_config)
      end

      it "creates the schema" do
        provisioner.provision(tenant, db_config)
        expect(mock_connection).to have_received(:execute).with(/CREATE SCHEMA IF NOT EXISTS/)
      end

      it "creates a tenant role" do
        provisioner.provision(tenant, db_config)
        expect(mock_connection).to have_received(:execute).with(/CREATE ROLE|GRANT USAGE ON SCHEMA/)
      end

      it "runs tenant migrations" do
        provisioner.provision(tenant, db_config)
        expect(ActiveRecord::MigrationContext).to have_received(:new).with(
          end_with("db/tenant_migrations"),
          anything
        )
      end
    end

    context "when schema creation raises StatementInvalid" do
      before do
        call_count = 0
        allow(mock_connection).to receive(:execute) do |sql|
          call_count += 1
          raise ActiveRecord::StatementInvalid, "permission denied" if sql.include?("CREATE SCHEMA")

          double("result", any?: false)
        end
      end

      it "returns Failure" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::DatabaseConnectionError)
      end
    end

    context "when schema name is unsafe" do
      let(:unsafe_tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid,
          slug: "acme-corp",
          name: "Acme",
          status: "provisioning",
          plan: "free",
          created_at: Time.current,
          updated_at: Time.current
        )
      end

      it "uses safe schema naming (tenant_ prefix + underscores only)" do
        expect(unsafe_tenant.schema_name).to match(/\Atenant_[a-z0-9_]+\z/)
      end
    end
  end

  describe "#deprovision" do
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

    context "when deprovision succeeds" do
      it "returns Success" do
        result = provisioner.deprovision(active_tenant)
        expect(result).to be_success
      end

      it "drops the schema" do
        provisioner.deprovision(active_tenant)
        expect(mock_connection).to have_received(:execute).with(/DROP SCHEMA IF EXISTS.*CASCADE/)
      end
    end

    context "when drop fails" do
      before do
        allow(mock_connection).to receive(:execute).with(/DROP SCHEMA/) do
          raise StandardError, "cannot drop"
        end
      end

      it "returns Failure" do
        result = provisioner.deprovision(active_tenant)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::TenantProvisioningError)
      end
    end
  end
end
