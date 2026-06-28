require "rails_helper"

RSpec.describe TenantResolver::TenantContext do
  let(:tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid, slug: "acme", name: "Acme",
      status: "active", plan: "free",
      created_at: Time.current, updated_at: Time.current
    )
  end

  let(:user) do
    Api::V1::CurrentUser.new(
      sub: SecureRandom.uuid, email: "user@acme.com",
      tenant_slug: "acme", role: "admin"
    )
  end

  after { described_class.clear }

  describe ".current_tenant=" do
    it "sets the current tenant on current thread" do
      described_class.current_tenant = tenant
      expect(described_class.current_tenant).to eq(tenant)
    end
  end

  describe ".current_user=" do
    it "sets the current user on current thread" do
      described_class.current_user = user
      expect(described_class.current_user).to eq(user)
    end
  end

  describe ".set" do
    it "sets tenant and user" do
      described_class.set(tenant: tenant, user: user)
      expect(described_class.current_tenant).to eq(tenant)
      expect(described_class.current_user).to eq(user)
    end

    it "allows nil user" do
      described_class.set(tenant: tenant, user: nil)
      expect(described_class.current_user).to be_nil
    end
  end

  describe ".clear" do
    it "clears both tenant and user" do
      described_class.set(tenant: tenant, user: user)
      described_class.clear
      expect(described_class.current_tenant).to be_nil
      expect(described_class.current_user).to be_nil
    end
  end

  describe ".with_tenant" do
    it "requires a block" do
      expect { described_class.with_tenant(tenant) }.to raise_error(ArgumentError, /Block required/)
    end

    it "yields with tenant set" do
      captured = nil
      described_class.with_tenant(tenant) { captured = described_class.current_tenant }
      expect(captured).to eq(tenant)
    end

    it "restores previous tenant after block" do
      outer = Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "outer", name: "Outer",
        status: "active", plan: "free",
        created_at: Time.current, updated_at: Time.current
      )
      described_class.current_tenant = outer

      described_class.with_tenant(tenant) { }
      expect(described_class.current_tenant).to eq(outer)
    end

    it "restores nil tenant if none was set" do
      described_class.with_tenant(tenant) { }
      expect(described_class.current_tenant).to be_nil
    end

    it "restores previous state even when block raises" do
      described_class.current_tenant = nil
      expect do
        described_class.with_tenant(tenant) { raise "boom" }
      end.to raise_error("boom")
      expect(described_class.current_tenant).to be_nil
    end

    it "is thread-safe (different threads get different values)" do
      values = {}

      t1 = Thread.new do
        tenant_a = Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "thread-a", name: "A",
          status: "active", plan: "free",
          created_at: Time.current, updated_at: Time.current
        )
        described_class.with_tenant(tenant_a) do
          sleep 0.05
          values[:t1] = described_class.current_tenant&.slug
        end
      end

      t2 = Thread.new do
        sleep 0.01
        tenant_b = Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "thread-b", name: "B",
          status: "active", plan: "free",
          created_at: Time.current, updated_at: Time.current
        )
        described_class.with_tenant(tenant_b) do
          values[:t2] = described_class.current_tenant&.slug
        end
      end

      [t1, t2].each(&:join)

      expect(values[:t1]).to eq("thread-a")
      expect(values[:t2]).to eq("thread-b")
    end
  end

  describe ".tenant_set?" do
    it "returns false when no tenant is set" do
      expect(described_class.tenant_set?).to be(false)
    end

    it "returns true when tenant is set" do
      described_class.current_tenant = tenant
      expect(described_class.tenant_set?).to be(true)
    end
  end

  describe ".require_tenant!" do
    it "returns the tenant when set" do
      described_class.current_tenant = tenant
      expect(described_class.require_tenant!).to eq(tenant)
    end

    it "raises TenantNotFoundError when no tenant is set" do
      expect { described_class.require_tenant! }
        .to raise_error(Domain::Shared::Errors::TenantNotFoundError)
    end
  end
end
