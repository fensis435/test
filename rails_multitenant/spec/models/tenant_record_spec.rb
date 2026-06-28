require "rails_helper"

RSpec.describe TenantRecord, type: :model do
  describe "validations" do
    subject(:tenant) { build(:tenant_record) }

    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:status).in_array(described_class::VALID_STATUSES) }
    it { is_expected.to validate_inclusion_of(:plan).in_array(described_class::VALID_PLANS) }

    context "slug format" do
      it "accepts valid slug" do
        tenant.slug = "valid-slug-01"
        expect(tenant).to be_valid
      end

      it "rejects slug with uppercase" do
        tenant.slug = "Invalid-Slug"
        expect(tenant).not_to be_valid
      end

      it "rejects slug with spaces" do
        tenant.slug = "invalid slug"
        expect(tenant).not_to be_valid
      end

      it "rejects single character slug" do
        tenant.slug = "a"
        expect(tenant).not_to be_valid
      end
    end

    context "slug uniqueness" do
      before { create(:tenant_record, slug: "taken-slug") }

      it "rejects duplicate slug" do
        tenant.slug = "taken-slug"
        expect(tenant).not_to be_valid
        expect(tenant.errors[:slug]).to include("has already been taken")
      end
    end

    context "name length" do
      it "rejects names over 255 characters" do
        tenant.name = "a" * 256
        expect(tenant).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active_tenant) { create(:tenant_record, status: "active") }
    let!(:suspended_tenant) { create(:tenant_record, status: "suspended", suspended_at: 1.hour.ago) }
    let!(:provisioning_tenant) { create(:tenant_record, :provisioning) }

    describe ".active" do
      it "returns only active tenants" do
        expect(described_class.active).to include(active_tenant)
        expect(described_class.active).not_to include(suspended_tenant, provisioning_tenant)
      end
    end

    describe ".suspended" do
      it "returns only suspended tenants" do
        expect(described_class.suspended).to include(suspended_tenant)
        expect(described_class.suspended).not_to include(active_tenant, provisioning_tenant)
      end
    end

    describe ".by_plan" do
      let!(:enterprise_tenant) { create(:tenant_record, :enterprise) }

      it "filters by plan" do
        expect(described_class.by_plan("enterprise")).to include(enterprise_tenant)
        expect(described_class.by_plan("enterprise")).not_to include(active_tenant)
      end
    end

    describe ".search_by_name" do
      let!(:named_tenant) { create(:tenant_record, name: "SpecialNameCorp") }

      it "performs case-insensitive name search" do
        expect(described_class.search_by_name("specialname")).to include(named_tenant)
        expect(described_class.search_by_name("SPECIALNAME")).to include(named_tenant)
        expect(described_class.search_by_name("notfound")).not_to include(named_tenant)
      end
    end
  end

  describe "callbacks" do
    it "normalizes slug to lowercase before validation" do
      tenant = build(:tenant_record, slug: "MY-TENANT-SLUG")
      # Note: validation will catch uppercase, but normalize fires first in before_validation
      # The slug format validator catches uppercase, so we test the normalization separately
      tenant.valid?
      # After normalize_slug callback, it becomes lowercase - validation will still fail
      # because normalization happens before validation
      expect(tenant.slug).to eq("my-tenant-slug")
    end

    it "strips whitespace from slug" do
      tenant = build(:tenant_record, slug: "  my-tenant  ")
      tenant.valid?
      expect(tenant.slug).to eq("my-tenant")
    end
  end
end
