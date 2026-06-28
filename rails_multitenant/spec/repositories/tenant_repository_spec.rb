require "rails_helper"

RSpec.describe Repositories::TenantRepository do
  subject(:repository) { described_class.new }

  let(:valid_domain_tenant) do
    Domain::Tenant::Tenant.create(slug: "acme-corp", name: "Acme Corp", plan: "professional")
  end

  let(:db_config) do
    Domain::Tenant::DatabaseConfig.for_aws(tenant_slug: "acme-corp", rds_host: "localhost")
  end

  describe "#save" do
    context "when creating a new tenant" do
      it "persists the tenant" do
        saved = repository.save(valid_domain_tenant)
        expect(TenantRecord.find_by(id: saved.id)).not_to be_nil
      end

      it "returns a Domain::Tenant::Tenant" do
        saved = repository.save(valid_domain_tenant)
        expect(saved).to be_a(Domain::Tenant::Tenant)
      end

      it "preserves all attributes" do
        saved = repository.save(valid_domain_tenant)
        expect(saved.slug).to eq("acme-corp")
        expect(saved.name).to eq("Acme Corp")
        expect(saved.plan).to eq("professional")
        expect(saved.status).to eq("provisioning")
      end

      it "persists database_config as JSONB" do
        tenant_with_config = valid_domain_tenant.assign_database_config(db_config)
        saved = repository.save(tenant_with_config)

        record = TenantRecord.find(saved.id)
        expect(record.database_config["host"]).to eq("localhost")
        expect(record.database_config["platform"]).to eq("aws")
      end
    end

    context "when updating an existing tenant" do
      let!(:saved_tenant) { repository.save(valid_domain_tenant) }

      it "updates the existing record" do
        activated = saved_tenant.activate
        updated = repository.save(activated)

        expect(updated.status).to eq("active")
        expect(TenantRecord.where(id: saved_tenant.id).count).to eq(1)
      end

      it "reflects the updated state in database" do
        activated = saved_tenant.activate
        repository.save(activated)
        expect(TenantRecord.find(saved_tenant.id).status).to eq("active")
      end
    end

    context "when validation fails" do
      it "raises ValidationError for duplicate slug" do
        repository.save(valid_domain_tenant)
        duplicate = Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid,
          slug: "acme-corp",
          name: "Duplicate",
          status: "provisioning",
          plan: "free",
          created_at: Time.current,
          updated_at: Time.current
        )
        expect { repository.save(duplicate) }
          .to raise_error(Domain::Shared::Errors::ValidationError)
      end
    end
  end

  describe "#find_by_id" do
    context "when tenant exists" do
      let!(:saved_tenant) { repository.save(valid_domain_tenant) }

      it "returns the domain tenant" do
        found = repository.find_by_id(saved_tenant.id)
        expect(found).to be_a(Domain::Tenant::Tenant)
        expect(found.id).to eq(saved_tenant.id)
      end

      it "maps database_config correctly" do
        tenant_with_config = saved_tenant.assign_database_config(db_config)
        repository.save(tenant_with_config)

        found = repository.find_by_id(saved_tenant.id)
        expect(found.database_config).to be_a(Domain::Tenant::DatabaseConfig)
        expect(found.database_config.host).to eq("localhost")
      end
    end

    context "when tenant does not exist" do
      it "returns nil" do
        expect(repository.find_by_id(SecureRandom.uuid)).to be_nil
      end
    end
  end

  describe "#find_by_slug" do
    let!(:saved_tenant) { repository.save(valid_domain_tenant) }

    it "returns the tenant by slug" do
      found = repository.find_by_slug("acme-corp")
      expect(found.id).to eq(saved_tenant.id)
    end

    it "is case-insensitive" do
      found = repository.find_by_slug("ACME-CORP")
      expect(found.id).to eq(saved_tenant.id)
    end

    it "returns nil when not found" do
      expect(repository.find_by_slug("nonexistent")).to be_nil
    end
  end

  describe "#find_all" do
    before do
      3.times.each_with_index do |_, i|
        tenant = Domain::Tenant::Tenant.create(
          slug: "tenant-#{i + 10}",
          name: "Tenant #{i}",
          plan: "free"
        )
        repository.save(tenant)
      end
    end

    it "returns all tenants ordered by created_at desc" do
      result = repository.find_all
      expect(result).to all(be_a(Domain::Tenant::Tenant))
      expect(result.size).to eq(3)
    end

    it "paginates results" do
      result = repository.find_all(page: 1, per_page: 2)
      expect(result.size).to eq(2)
    end

    it "filters by status" do
      tenant = Domain::Tenant::Tenant.create(slug: "active-one", name: "Active", plan: "free").activate
      repository.save(tenant)
      result = repository.find_all(filters: { status: "active" })
      expect(result).to all(have_attributes(status: "active"))
    end

    it "filters by plan" do
      result = repository.find_all(filters: { plan: "free" })
      expect(result).to all(have_attributes(plan: "free"))
    end

    it "filters by name substring" do
      result = repository.find_all(filters: { name: "Tenant 0" })
      expect(result.map(&:name)).to include("Tenant 0")
    end
  end

  describe "#exists_by_slug?" do
    let!(:saved_tenant) { repository.save(valid_domain_tenant) }

    it "returns true when slug exists" do
      expect(repository.exists_by_slug?("acme-corp")).to be(true)
    end

    it "returns false when slug does not exist" do
      expect(repository.exists_by_slug?("no-such-tenant")).to be(false)
    end

    it "is case-insensitive" do
      expect(repository.exists_by_slug?("ACME-CORP")).to be(true)
    end
  end

  describe "#count_by_status" do
    before do
      2.times.each_with_index do |_, i|
        t = Domain::Tenant::Tenant.create(slug: "active-#{i + 1}", name: "Active #{i}", plan: "free").activate
        repository.save(t)
      end
      susp = Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "susp-1", name: "Susp",
        status: "suspended", plan: "free",
        created_at: Time.current, updated_at: Time.current,
        suspended_at: 1.hour.ago
      )
      repository.save(susp)
    end

    it "counts tenants by status" do
      expect(repository.count_by_status("active")).to eq(2)
      expect(repository.count_by_status("suspended")).to eq(1)
      expect(repository.count_by_status("provisioning")).to eq(0)
    end
  end

  describe "#delete" do
    let!(:saved_tenant) { repository.save(valid_domain_tenant) }

    it "removes the tenant from the database" do
      repository.delete(saved_tenant)
      expect(TenantRecord.find_by(id: saved_tenant.id)).to be_nil
    end

    it "returns true on success" do
      expect(repository.delete(saved_tenant)).to be(true)
    end

    it "returns false when tenant not found" do
      phantom = Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "phantom", name: "Phantom",
        status: "provisioning", plan: "free",
        created_at: Time.current, updated_at: Time.current
      )
      expect(repository.delete(phantom)).to be(false)
    end
  end
end
