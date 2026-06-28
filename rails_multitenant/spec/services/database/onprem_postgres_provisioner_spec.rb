require "rails_helper"

RSpec.describe Services::Database::OnpremPostgresProvisioner do
  subject(:provisioner) { described_class.new(k8s_client: k8s_client, logger: logger) }

  let(:k8s_client) { instance_double(Services::Kubernetes::Client) }
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
    Domain::Tenant::DatabaseConfig.for_onprem(tenant_slug: "acme-corp", namespace: "default")
  end

  before do
    allow(Rails.application.config.x.database).to receive(:onprem_namespace).and_return("default")

    allow(k8s_client).to receive(:create_secret)
    allow(k8s_client).to receive(:apply_statefulset)
    allow(k8s_client).to receive(:apply_service)
    allow(k8s_client).to receive(:statefulset_ready?).and_return(true)

    pool = instance_double(ConnectionPool)
    allow(DatabaseSwitcher::ConnectionPoolRegistry).to receive(:instance).and_return(
      instance_double(DatabaseSwitcher::ConnectionPoolRegistry, fetch_or_create: pool)
    )
    allow(pool).to receive(:with_connection).and_yield(ActiveRecord::Base.connection)

    migration_context = instance_double(ActiveRecord::MigrationContext)
    allow(ActiveRecord::MigrationContext).to receive(:new).and_return(migration_context)
    allow(migration_context).to receive(:migrate)
  end

  describe "#provision" do
    context "when provisioning succeeds" do
      it "returns Success with config" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_success
        expect(result.value!).to eq(db_config)
      end

      it "creates the Kubernetes secret" do
        provisioner.provision(tenant, db_config)
        expect(k8s_client).to have_received(:create_secret).with(
          hash_including(name: "postgres-acme-corp-credentials", namespace: "default")
        )
      end

      it "applies the StatefulSet manifest" do
        provisioner.provision(tenant, db_config)
        expect(k8s_client).to have_received(:apply_statefulset).once
      end

      it "applies the Service manifest" do
        provisioner.provision(tenant, db_config)
        expect(k8s_client).to have_received(:apply_service).once
      end

      it "waits for pod readiness" do
        provisioner.provision(tenant, db_config)
        expect(k8s_client).to have_received(:statefulset_ready?).with(
          name: "postgres-acme-corp", namespace: "default"
        ).at_least(:once)
      end

      it "runs tenant migrations after pod is ready" do
        provisioner.provision(tenant, db_config)
        expect(ActiveRecord::MigrationContext).to have_received(:new)
      end
    end

    context "when pod does not become ready within timeout" do
      before do
        allow(k8s_client).to receive(:statefulset_ready?).and_return(false)
        stub_const("Services::Database::OnpremPostgresProvisioner::PROVISION_TIMEOUT", 0)
        stub_const("Services::Database::OnpremPostgresProvisioner::PROVISION_POLL_INTERVAL", 0)
      end

      it "returns Failure with TenantProvisioningError" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::TenantProvisioningError)
        expect(result.failure.message).to include("ready")
      end
    end

    context "when K8s client raises" do
      before do
        allow(k8s_client).to receive(:apply_statefulset).and_raise(StandardError, "K8s API error")
      end

      it "returns Failure" do
        result = provisioner.provision(tenant, db_config)
        expect(result).to be_failure
        expect(result.failure.message).to include("K8s API error")
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

    before do
      allow(k8s_client).to receive(:delete_statefulset)
      allow(k8s_client).to receive(:delete_service)
      allow(k8s_client).to receive(:delete_secret)
      allow(k8s_client).to receive(:delete_pvc)
    end

    it "returns Success" do
      result = provisioner.deprovision(active_tenant)
      expect(result).to be_success
    end

    it "deletes all K8s resources" do
      provisioner.deprovision(active_tenant)
      expect(k8s_client).to have_received(:delete_statefulset).with(name: "postgres-acme-corp", namespace: "default")
      expect(k8s_client).to have_received(:delete_service).with(name: "postgres-acme-corp", namespace: "default")
      expect(k8s_client).to have_received(:delete_secret).with(name: "postgres-acme-corp-credentials", namespace: "default")
      expect(k8s_client).to have_received(:delete_pvc).with(name: "data-postgres-acme-corp-0", namespace: "default")
    end

    context "when K8s client raises" do
      before do
        allow(k8s_client).to receive(:delete_statefulset).and_raise(StandardError, "not found")
      end

      it "returns Failure" do
        result = provisioner.deprovision(active_tenant)
        expect(result).to be_failure
      end
    end
  end
end
