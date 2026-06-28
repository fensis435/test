require "rails_helper"

RSpec.describe Serializers::TenantSerializer do
  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
  end

  let(:tenant) do
    Domain::Tenant::Tenant.new(
      id: "uuid-1234",
      slug: "acme-corp",
      name: "Acme Corp",
      status: "active",
      plan: "professional",
      settings: {
        "max_users" => 100,
        "api_rate_limit" => 2000,
        "password" => "secret",
        "suspension_reason" => "Non-payment"
      },
      database_config: db_config,
      created_at: Time.zone.parse("2024-01-01T00:00:00Z"),
      updated_at: Time.zone.parse("2024-06-01T00:00:00Z"),
      suspended_at: nil
    )
  end

  subject(:serialized) { described_class.new(tenant).as_json }

  it "includes id" do
    expect(serialized[:id]).to eq("uuid-1234")
  end

  it "includes slug" do
    expect(serialized[:slug]).to eq("acme-corp")
  end

  it "includes name" do
    expect(serialized[:name]).to eq("Acme Corp")
  end

  it "includes status" do
    expect(serialized[:status]).to eq("active")
  end

  it "includes plan" do
    expect(serialized[:plan]).to eq("professional")
  end

  it "includes database_provisioned flag" do
    expect(serialized[:database_provisioned]).to be(true)
  end

  it "formats created_at as ISO8601" do
    expect(serialized[:created_at]).to eq("2024-01-01T00:00:00Z")
  end

  it "formats updated_at as ISO8601" do
    expect(serialized[:updated_at]).to eq("2024-06-01T00:00:00Z")
  end

  it "returns nil for suspended_at when not suspended" do
    expect(serialized[:suspended_at]).to be_nil
  end

  describe "settings sanitization" do
    it "excludes password fields" do
      expect(serialized[:settings]).not_to have_key("password")
    end

    it "excludes suspension_reason" do
      expect(serialized[:settings]).not_to have_key("suspension_reason")
    end

    it "includes non-sensitive settings" do
      expect(serialized[:settings]["max_users"]).to eq(100)
      expect(serialized[:settings]["api_rate_limit"]).to eq(2000)
    end
  end

  context "when tenant is unprovisioned" do
    let(:tenant) do
      Domain::Tenant::Tenant.new(
        id: "uuid-5678",
        slug: "new-tenant",
        name: "New",
        status: "provisioning",
        plan: "free",
        database_config: nil,
        created_at: Time.current,
        updated_at: Time.current
      )
    end

    it "database_provisioned is false" do
      expect(serialized[:database_provisioned]).to be(false)
    end
  end
end
