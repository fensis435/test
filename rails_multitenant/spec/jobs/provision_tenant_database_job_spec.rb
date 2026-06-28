require "rails_helper"

RSpec.describe ProvisionTenantDatabaseJob, type: :job do
  include Dry::Monads[:result]

  let(:tenant_repository) { instance_double(Repositories::TenantRepository) }
  let(:db_provisioner) { instance_double(Services::Database::DatabaseProvisioner) }
  let(:connection_resolver) { instance_double(DatabaseSwitcher::ConnectionResolver) }

  let(:tenant_id) { SecureRandom.uuid }
  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
  end

  let(:unprovisioned_tenant) do
    Domain::Tenant::Tenant.new(
      id: tenant_id,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "provisioning",
      plan: "professional",
      database_config: nil,
      created_at: 1.hour.ago,
      updated_at: 1.hour.ago
    )
  end

  let(:provisioned_tenant) do
    Domain::Tenant::Tenant.new(
      id: tenant_id,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "active",
      plan: "professional",
      database_config: db_config,
      created_at: 1.hour.ago,
      updated_at: Time.current
    )
  end

  before do
    allow(Repositories::TenantRepository).to receive(:new).and_return(tenant_repository)
    allow(Services::Database::DatabaseProvisioner).to receive(:new).and_return(db_provisioner)
    allow(DatabaseSwitcher::ConnectionResolver).to receive(:new).and_return(connection_resolver)
  end

  describe "#perform" do
    context "when tenant exists and is not yet provisioned" do
      before do
        allow(tenant_repository).to receive(:find_by_id).with(tenant_id).and_return(unprovisioned_tenant)
        allow(connection_resolver).to receive(:build_config_for_provisioning).and_return(db_config)
        allow(db_provisioner).to receive(:provision).and_return(Success(db_config))
        allow(tenant_repository).to receive(:save).and_return(provisioned_tenant)
      end

      it "provisions the database" do
        described_class.new.perform(tenant_id)
        expect(db_provisioner).to have_received(:provision).with(unprovisioned_tenant, db_config)
      end

      it "saves the activated tenant" do
        described_class.new.perform(tenant_id)
        expect(tenant_repository).to have_received(:save).once
      end
    end

    context "when tenant does not exist" do
      before do
        allow(tenant_repository).to receive(:find_by_id).with(tenant_id).and_return(nil)
      end

      it "does not call provisioner" do
        described_class.new.perform(tenant_id)
        expect(db_provisioner).not_to have_received(:provision)
      end
    end

    context "when tenant is already provisioned" do
      before do
        allow(tenant_repository).to receive(:find_by_id).with(tenant_id).and_return(provisioned_tenant)
      end

      it "does not call provisioner" do
        described_class.new.perform(tenant_id)
        expect(db_provisioner).not_to have_received(:provision)
      end
    end

    context "when provisioning fails" do
      before do
        allow(tenant_repository).to receive(:find_by_id).with(tenant_id).and_return(unprovisioned_tenant)
        allow(connection_resolver).to receive(:build_config_for_provisioning).and_return(db_config)
        allow(db_provisioner).to receive(:provision).and_return(
          Failure(Domain::Shared::Errors::TenantProvisioningError.new("RDS unavailable"))
        )
      end

      it "raises an error to trigger Sidekiq retry" do
        expect { described_class.new.perform(tenant_id) }.to raise_error("RDS unavailable")
      end
    end
  end

  describe "job configuration" do
    it "is enqueued on the provisioning queue" do
      expect(described_class.queue_name).to eq("provisioning")
    end
  end
end
