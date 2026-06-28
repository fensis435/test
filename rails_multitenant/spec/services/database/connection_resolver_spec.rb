require "rails_helper"

RSpec.describe DatabaseSwitcher::ConnectionResolver do
  describe "#resolve" do
    let(:db_config) do
      Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
    end

    let(:active_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "acme-corp", name: "Acme Corp",
        status: "active", plan: "professional",
        database_config: db_config,
        created_at: 2.hours.ago, updated_at: 1.hour.ago
      )
    end

    let(:unprovisioned_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "acme-corp", name: "Acme Corp",
        status: "provisioning", plan: "professional",
        database_config: nil,
        created_at: 1.hour.ago, updated_at: 1.hour.ago
      )
    end

    context "when tenant has database config" do
      it "returns the existing config" do
        resolver = described_class.new
        expect(resolver.resolve(active_tenant)).to eq(db_config)
      end
    end

    context "when tenant has no database config" do
      it "raises DatabaseConnectionError" do
        resolver = described_class.new
        expect { resolver.resolve(unprovisioned_tenant) }
          .to raise_error(Domain::Shared::Errors::DatabaseConnectionError, /no database configuration/)
      end
    end
  end

  describe "#build_config_for_provisioning" do
    context "on AWS platform" do
      subject(:resolver) { described_class.new(platform: "aws") }

      before do
        allow(ENV).to receive(:fetch).with("RDS_HOST").and_return("rds.example.com")
        allow(ENV).to receive(:fetch).with("RDS_PORT", 5432).and_return(5432)
      end

      let(:tenant) do
        Domain::Tenant::Tenant.create(slug: "acme-corp", name: "Acme", plan: "free")
      end

      it "returns AWS config" do
        config = resolver.build_config_for_provisioning(tenant)
        expect(config.platform).to eq("aws")
        expect(config.host).to eq("rds.example.com")
      end

      it "raises when RDS_HOST not set" do
        allow(ENV).to receive(:fetch).with("RDS_HOST").and_raise(KeyError)
        expect { resolver.build_config_for_provisioning(tenant) }
          .to raise_error(Domain::Shared::Errors::DatabaseConnectionError)
      end
    end

    context "on on-prem platform" do
      subject(:resolver) { described_class.new(platform: "onprem") }

      let(:tenant) do
        Domain::Tenant::Tenant.create(slug: "acme-corp", name: "Acme", plan: "free")
      end

      before do
        allow(Rails.application.config.x.database).to receive(:onprem_namespace).and_return("production")
      end

      it "returns on-prem config" do
        config = resolver.build_config_for_provisioning(tenant)
        expect(config.platform).to eq("onprem")
        expect(config.host).to include("acme-corp")
        expect(config.host).to include("production.svc.cluster.local")
      end
    end

    context "with unknown platform" do
      subject(:resolver) { described_class.new(platform: "unknown") }

      let(:tenant) do
        Domain::Tenant::Tenant.create(slug: "acme-corp", name: "Acme", plan: "free")
      end

      it "raises DatabaseConnectionError" do
        expect { resolver.build_config_for_provisioning(tenant) }
          .to raise_error(Domain::Shared::Errors::DatabaseConnectionError, /Unknown platform/)
      end
    end
  end
end
