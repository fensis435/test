require "rails_helper"

RSpec.describe Services::Tenant::TenantProvisioner do
  subject(:provisioner) do
    described_class.new(
      tenant_repository: tenant_repository,
      database_provisioner: database_provisioner,
      connection_resolver: connection_resolver
    )
  end

  let(:tenant_repository) { instance_double(Repositories::TenantRepository) }
  let(:database_provisioner) { instance_double(Services::Database::DatabaseProvisioner) }
  let(:connection_resolver) { instance_double(DatabaseSwitcher::ConnectionResolver) }

  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "rds.example.com")
  end

  describe "#provision" do
    before do
      allow(tenant_repository).to receive(:exists_by_slug?).with("acme-corp").and_return(false)
      allow(tenant_repository).to receive(:save).and_return(provisioning_tenant)
      allow(connection_resolver).to receive(:build_config_for_provisioning).and_return(db_config)
      allow(database_provisioner).to receive(:provision).and_return(Success(db_config))
      allow(tenant_repository).to receive(:save).and_return(active_tenant)
    end

    let(:provisioning_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "provisioning",
        plan: "professional",
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    let(:active_tenant) do
      Domain::Tenant::Tenant.new(
        id: provisioning_tenant.id,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "active",
        plan: "professional",
        database_config: db_config,
        created_at: provisioning_tenant.created_at,
        updated_at: Time.current
      )
    end

    context "when provisioning succeeds" do
      it "returns a Success result" do
        result = provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(result).to be_success
      end

      it "saves the tenant twice (create + activate)" do
        provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(tenant_repository).to have_received(:save).at_least(:twice)
      end

      it "calls database provisioner" do
        provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(database_provisioner).to have_received(:provision).once
      end

      it "calls connection resolver for config" do
        provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(connection_resolver).to have_received(:build_config_for_provisioning)
      end
    end

    context "when slug is already taken" do
      before do
        allow(tenant_repository).to receive(:exists_by_slug?).with("acme-corp").and_return(true)
      end

      it "returns a Failure with ConflictError" do
        result = provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::ConflictError)
      end

      it "does not call the database provisioner" do
        provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(database_provisioner).not_to have_received(:provision)
      end
    end

    context "when domain validation fails" do
      it "returns Failure for invalid slug" do
        result = provisioner.provision(slug: "INVALID SLUG!", name: "Acme", plan: "free")
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::ValidationError)
      end

      it "returns Failure for invalid plan" do
        result = provisioner.provision(slug: "valid-slug", name: "Acme", plan: "invalid-plan")
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::ValidationError)
      end
    end

    context "when database provisioner fails" do
      before do
        allow(database_provisioner).to receive(:provision).and_return(
          Failure(Domain::Shared::Errors::TenantProvisioningError.new("RDS error"))
        )
      end

      it "returns a Failure" do
        result = provisioner.provision(slug: "acme-corp", name: "Acme Corp", plan: "professional")
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::TenantProvisioningError)
      end
    end
  end

  describe "#suspend" do
    let(:active_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "active",
        plan: "professional",
        created_at: 2.hours.ago,
        updated_at: 1.hour.ago
      )
    end

    let(:suspended_tenant) do
      Domain::Tenant::Tenant.new(
        id: active_tenant.id,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "suspended",
        plan: "professional",
        created_at: active_tenant.created_at,
        updated_at: Time.current,
        suspended_at: Time.current
      )
    end

    before do
      allow(tenant_repository).to receive(:save).and_return(suspended_tenant)
    end

    it "returns Success with suspended tenant" do
      result = provisioner.suspend(active_tenant, reason: "Non-payment")
      expect(result).to be_success
      expect(result.value!.status).to eq("suspended")
    end

    it "persists the suspension" do
      provisioner.suspend(active_tenant)
      expect(tenant_repository).to have_received(:save)
    end

    context "when tenant cannot be suspended" do
      let(:provisioning_tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "acme", name: "Acme",
          status: "provisioning", plan: "free",
          created_at: Time.current, updated_at: Time.current
        )
      end

      it "returns Failure with InvalidStateTransitionError" do
        result = provisioner.suspend(provisioning_tenant)
        expect(result).to be_failure
        expect(result.failure).to be_a(Domain::Shared::Errors::InvalidStateTransitionError)
      end
    end
  end

  describe "#activate" do
    let(:suspended_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "suspended",
        plan: "professional",
        created_at: 2.hours.ago,
        updated_at: 1.hour.ago,
        suspended_at: 1.hour.ago
      )
    end

    let(:active_tenant) do
      Domain::Tenant::Tenant.new(
        id: suspended_tenant.id,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "active",
        plan: "professional",
        created_at: suspended_tenant.created_at,
        updated_at: Time.current
      )
    end

    before do
      allow(tenant_repository).to receive(:save).and_return(active_tenant)
    end

    it "returns Success with active tenant" do
      result = provisioner.activate(suspended_tenant)
      expect(result).to be_success
      expect(result.value!.status).to eq("active")
    end
  end

  describe "#terminate" do
    let(:active_tenant) do
      db_config = Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "rds.example.com")
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

    let(:terminated_tenant) do
      Domain::Tenant::Tenant.new(
        id: active_tenant.id,
        slug: "acme-corp",
        name: "Acme Corp",
        status: "terminated",
        plan: "professional",
        created_at: active_tenant.created_at,
        updated_at: Time.current
      )
    end

    before do
      allow(tenant_repository).to receive(:save).and_return(terminated_tenant)
      allow(database_provisioner).to receive(:deprovision).and_return(Success(true))
    end

    it "returns Success with terminated tenant" do
      result = provisioner.terminate(active_tenant)
      expect(result).to be_success
      expect(result.value!.status).to eq("terminated")
    end

    it "deprovisionsthe database" do
      provisioner.terminate(active_tenant)
      expect(database_provisioner).to have_received(:deprovision).with(active_tenant)
    end
  end
end
