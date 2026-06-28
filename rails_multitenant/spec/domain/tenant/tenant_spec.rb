require "rails_helper"

RSpec.describe Domain::Tenant::Tenant do
  describe ".create" do
    subject(:tenant) do
      described_class.create(slug: "acme-corp", name: "Acme Corp", plan: "professional")
    end

    it "creates a tenant with provisioning status" do
      expect(tenant.status).to eq("provisioning")
    end

    it "assigns a UUID id" do
      expect(tenant.id).to match(/\A[0-9a-f\-]{36}\z/)
    end

    it "normalizes slug to lowercase" do
      t = described_class.create(slug: "ACME-CORP", name: "Acme", plan: "free")
      expect(t.slug).to eq("acme-corp")
    end

    it "strips whitespace from name" do
      t = described_class.create(slug: "acme", name: "  Acme Corp  ", plan: "free")
      expect(t.name).to eq("Acme Corp")
    end

    it "merges default settings" do
      expect(tenant.settings).to include(
        "max_users" => 100,
        "storage_gb" => 100,
        "api_rate_limit" => 2000
      )
    end

    it "merges custom settings over defaults" do
      t = described_class.create(slug: "acme", name: "Acme", plan: "free", settings: { "mfa_required" => true })
      expect(t.settings["mfa_required"]).to be(true)
    end

    it "sets created_at and updated_at" do
      freeze_time do
        expect(tenant.created_at).to eq(Time.current)
        expect(tenant.updated_at).to eq(Time.current)
      end
    end

    context "with invalid slug" do
      it "raises ValidationError when blank" do
        expect { described_class.create(slug: "", name: "Acme", plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Slug is required/)
      end

      it "raises ValidationError when too short" do
        expect { described_class.create(slug: "a", name: "Acme", plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Slug format is invalid/)
      end

      it "raises ValidationError when contains uppercase" do
        expect { described_class.create(slug: "Acme-Corp", name: "Acme", plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Slug format is invalid/)
      end

      it "raises ValidationError when contains spaces" do
        expect { described_class.create(slug: "acme corp", name: "Acme", plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Slug format is invalid/)
      end

      it "raises ValidationError when too long" do
        long_slug = "a" * 64
        expect { described_class.create(slug: long_slug, name: "Acme", plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Slug format is invalid/)
      end
    end

    context "with invalid name" do
      it "raises ValidationError when blank" do
        expect { described_class.create(slug: "acme-corp", name: "", plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Name is required/)
      end

      it "raises ValidationError when too long" do
        expect { described_class.create(slug: "acme-corp", name: "a" * 256, plan: "free") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Name is too long/)
      end
    end

    context "with invalid plan" do
      it "raises ValidationError" do
        expect { described_class.create(slug: "acme-corp", name: "Acme", plan: "invalid") }
          .to raise_error(Domain::Shared::Errors::ValidationError, /Invalid plan/)
      end
    end
  end

  describe "#activate" do
    context "when tenant is provisioning" do
      let(:tenant) { described_class.create(slug: "acme-corp", name: "Acme", plan: "free") }

      it "returns a new tenant with active status" do
        activated = tenant.activate
        expect(activated.status).to eq("active")
      end

      it "does not mutate original tenant" do
        tenant.activate
        expect(tenant.status).to eq("provisioning")
      end

      it "updates updated_at" do
        Timecop.freeze(1.hour.from_now) do
          activated = tenant.activate
          expect(activated.updated_at).to be > tenant.updated_at
        end
      end

      it "clears suspended_at" do
        activated = tenant.activate
        expect(activated.suspended_at).to be_nil
      end
    end

    context "when tenant is suspended" do
      let(:tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "acme", name: "Acme",
          status: "suspended", plan: "free", suspended_at: 1.hour.ago,
          created_at: 2.hours.ago, updated_at: 1.hour.ago
        )
      end

      it "returns active tenant" do
        expect(tenant.activate.status).to eq("active")
      end
    end

    context "when tenant is terminated" do
      let(:tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "acme", name: "Acme",
          status: "terminated", plan: "free",
          created_at: 2.hours.ago, updated_at: 1.hour.ago
        )
      end

      it "raises InvalidStateTransitionError" do
        expect { tenant.activate }
          .to raise_error(Domain::Shared::Errors::InvalidStateTransitionError, /Cannot activate/)
      end
    end
  end

  describe "#suspend" do
    let(:tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "acme", name: "Acme",
        status: "active", plan: "free",
        created_at: 2.hours.ago, updated_at: 1.hour.ago
      )
    end

    it "returns tenant with suspended status" do
      suspended = tenant.suspend
      expect(suspended.status).to eq("suspended")
    end

    it "sets suspended_at" do
      freeze_time do
        suspended = tenant.suspend
        expect(suspended.suspended_at).to eq(Time.current)
      end
    end

    it "stores suspension reason in settings" do
      suspended = tenant.suspend(reason: "Non-payment")
      expect(suspended.settings["suspension_reason"]).to eq("Non-payment")
    end

    it "raises InvalidStateTransitionError when not active" do
      provisioning = Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "acme", name: "Acme",
        status: "provisioning", plan: "free",
        created_at: 1.hour.ago, updated_at: 1.hour.ago
      )
      expect { provisioning.suspend }.to raise_error(Domain::Shared::Errors::InvalidStateTransitionError)
    end
  end

  describe "#terminate" do
    %w[active suspended provisioning].each do |from_status|
      it "allows termination from #{from_status}" do
        tenant = Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "acme", name: "Acme",
          status: from_status, plan: "free",
          created_at: 1.hour.ago, updated_at: 1.hour.ago
        )
        expect(tenant.terminate.status).to eq("terminated")
      end
    end

    it "raises InvalidStateTransitionError when already terminated" do
      tenant = Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "acme", name: "Acme",
        status: "terminated", plan: "free",
        created_at: 1.hour.ago, updated_at: 1.hour.ago
      )
      expect { tenant.terminate }.to raise_error(Domain::Shared::Errors::InvalidStateTransitionError)
    end
  end

  describe "#assign_database_config" do
    let(:tenant) { described_class.create(slug: "acme-corp", name: "Acme", plan: "free") }
    let(:config) do
      Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "rds.example.com")
    end

    it "returns new tenant with config assigned" do
      updated = tenant.assign_database_config(config)
      expect(updated.database_config).to eq(config)
    end

    it "does not mutate the original tenant" do
      tenant.assign_database_config(config)
      expect(tenant.database_config).to be_nil
    end
  end

  describe "#database_provisioned?" do
    it "returns false when database_config is nil" do
      tenant = described_class.create(slug: "acme-corp", name: "Acme", plan: "free")
      expect(tenant.database_provisioned?).to be(false)
    end

    it "returns true when database_config is present" do
      config = Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "rds.example.com")
      tenant = described_class.create(slug: "acme-corp", name: "Acme", plan: "free")
      expect(tenant.assign_database_config(config).database_provisioned?).to be(true)
    end
  end

  describe "#schema_name" do
    it "converts slug hyphens to underscores with tenant_ prefix" do
      tenant = described_class.create(slug: "acme-corp", name: "Acme", plan: "free")
      expect(tenant.schema_name).to eq("tenant_acme_corp")
    end
  end

  describe "#==" do
    it "returns true for same id" do
      id = SecureRandom.uuid
      a = Domain::Tenant::Tenant.new(id: id, slug: "a", name: "A", status: "active", plan: "free", created_at: Time.current, updated_at: Time.current)
      b = Domain::Tenant::Tenant.new(id: id, slug: "b", name: "B", status: "suspended", plan: "starter", created_at: 1.day.ago, updated_at: 1.day.ago)
      expect(a).to eq(b)
    end

    it "returns false for different id" do
      a = described_class.create(slug: "acme-aa", name: "A", plan: "free")
      b = described_class.create(slug: "acme-bb", name: "B", plan: "free")
      expect(a).not_to eq(b)
    end
  end

  describe "#to_h" do
    it "returns a hash with all fields" do
      tenant = described_class.create(slug: "acme-corp", name: "Acme", plan: "free")
      hash = tenant.to_h
      expect(hash).to include(:id, :slug, :name, :status, :plan, :settings, :created_at, :updated_at)
    end
  end

  describe "status predicates" do
    %w[active suspended provisioning terminated].each do |status|
      it "#{status}? returns true for #{status} tenant" do
        tenant = Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "t", name: "T",
          status: status, plan: "free",
          created_at: Time.current, updated_at: Time.current
        )
        expect(tenant.public_send(:"#{status}?")).to be(true)
      end
    end
  end
end
