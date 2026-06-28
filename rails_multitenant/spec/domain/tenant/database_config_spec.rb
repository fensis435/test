require "rails_helper"

RSpec.describe Domain::Tenant::DatabaseConfig do
  describe ".for_aws" do
    subject(:config) do
      described_class.for_aws(tenant_slug: "acme-corp", rds_host: "db.rds.amazonaws.com", rds_port: 5432)
    end

    it "sets platform to aws" do
      expect(config.platform).to eq("aws")
    end

    it "sets endpoint_type to rds" do
      expect(config.endpoint_type).to eq("rds")
    end

    it "converts hyphens to underscores in database name" do
      expect(config.database).to eq("tenant_acme_corp")
    end

    it "generates username from slug" do
      expect(config.username).to eq("tenant_acme_corp_user")
    end

    it "sets ssl_mode to require" do
      expect(config.ssl_mode).to eq("require")
    end

    it "sets schema to public" do
      expect(config.schema).to eq("public")
    end

    it "uses provided host" do
      expect(config.host).to eq("db.rds.amazonaws.com")
    end
  end

  describe ".for_onprem" do
    subject(:config) do
      described_class.for_onprem(tenant_slug: "acme-corp", namespace: "production")
    end

    it "sets platform to onprem" do
      expect(config.platform).to eq("onprem")
    end

    it "sets endpoint_type to pod" do
      expect(config.endpoint_type).to eq("pod")
    end

    it "builds cluster-local hostname" do
      expect(config.host).to eq("postgres-acme-corp.production.svc.cluster.local")
    end

    it "sets ssl_mode to disable for internal cluster" do
      expect(config.ssl_mode).to eq("disable")
    end

    it "sets username to tenant_user" do
      expect(config.username).to eq("tenant_user")
    end
  end

  describe "#aws?" do
    it "returns true for aws platform" do
      config = described_class.for_aws(tenant_slug: "acme", rds_host: "localhost")
      expect(config.aws?).to be(true)
    end

    it "returns false for onprem platform" do
      config = described_class.for_onprem(tenant_slug: "acme", namespace: "default")
      expect(config.aws?).to be(false)
    end
  end

  describe "#onprem?" do
    it "returns true for onprem platform" do
      config = described_class.for_onprem(tenant_slug: "acme", namespace: "default")
      expect(config.onprem?).to be(true)
    end
  end

  describe "#connection_string" do
    it "includes sslmode for aws config" do
      config = described_class.for_aws(tenant_slug: "acme", rds_host: "db.example.com")
      expect(config.connection_string).to include("sslmode=require")
    end

    it "includes credentials when password provided" do
      config = described_class.for_aws(tenant_slug: "acme", rds_host: "db.example.com")
      cs = config.connection_string(password: "secret")
      expect(cs).to include("secret@")
    end

    it "omits password when not provided" do
      config = described_class.for_aws(tenant_slug: "acme", rds_host: "db.example.com")
      cs = config.connection_string
      expect(cs).not_to include("@db.example.com".prepend(":"))
    end
  end

  describe "#to_h" do
    it "includes all required keys" do
      config = described_class.for_aws(tenant_slug: "acme", rds_host: "localhost")
      expect(config.to_h).to include(
        :host, :port, :database, :username, :schema, :platform, :endpoint_type, :ssl_mode, :pool_size
      )
    end
  end

  describe "#==" do
    it "returns true for identical configs" do
      a = described_class.for_aws(tenant_slug: "acme", rds_host: "localhost")
      b = described_class.for_aws(tenant_slug: "acme", rds_host: "localhost")
      expect(a).to eq(b)
    end

    it "returns false for different configs" do
      a = described_class.for_aws(tenant_slug: "acme", rds_host: "host-a")
      b = described_class.for_aws(tenant_slug: "acme", rds_host: "host-b")
      expect(a).not_to eq(b)
    end
  end
end
