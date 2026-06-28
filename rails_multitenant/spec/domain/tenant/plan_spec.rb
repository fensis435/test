require "rails_helper"

RSpec.describe Domain::Tenant::Plan do
  describe ".new" do
    Domain::Tenant::Plan::VALID_PLANS.each do |plan_name|
      it "accepts valid plan: #{plan_name}" do
        expect { described_class.new(plan_name) }.not_to raise_error
      end
    end

    it "raises ValidationError for unknown plan" do
      expect { described_class.new("mega") }
        .to raise_error(Domain::Shared::Errors::ValidationError, /Invalid plan/)
    end
  end

  describe "#limits" do
    it "returns the limits hash for the plan" do
      plan = described_class.new("professional")
      expect(plan.limits).to include(
        max_users: 100,
        storage_gb: 100,
        api_rate_limit: 2000,
        sso_enabled: true
      )
    end
  end

  describe "#max_users" do
    it "returns 5 for free plan" do
      expect(described_class.new("free").max_users).to eq(5)
    end

    it "returns Float::INFINITY for enterprise plan" do
      expect(described_class.new("enterprise").max_users).to eq(Float::INFINITY)
    end
  end

  describe "#sso_enabled?" do
    it "returns false for starter plan" do
      expect(described_class.new("starter").sso_enabled?).to be(false)
    end

    it "returns true for enterprise plan" do
      expect(described_class.new("enterprise").sso_enabled?).to be(true)
    end
  end

  describe "#upgradeable_to?" do
    it "returns true when upgrading to higher tier" do
      plan = described_class.new("free")
      expect(plan.upgradeable_to?("starter")).to be(true)
      expect(plan.upgradeable_to?("professional")).to be(true)
      expect(plan.upgradeable_to?("enterprise")).to be(true)
    end

    it "returns false when downgrading" do
      plan = described_class.new("professional")
      expect(plan.upgradeable_to?("starter")).to be(false)
      expect(plan.upgradeable_to?("free")).to be(false)
    end

    it "returns false for same plan" do
      plan = described_class.new("free")
      expect(plan.upgradeable_to?("free")).to be(false)
    end
  end

  describe "#enterprise?" do
    it "returns true for enterprise" do
      expect(described_class.new("enterprise").enterprise?).to be(true)
    end

    it "returns false for others" do
      expect(described_class.new("professional").enterprise?).to be(false)
    end
  end

  describe "#==" do
    it "returns true for same plan name" do
      expect(described_class.new("free")).to eq(described_class.new("free"))
    end

    it "returns false for different plan names" do
      expect(described_class.new("free")).not_to eq(described_class.new("starter"))
    end
  end

  describe "#to_s" do
    it "returns the plan name" do
      expect(described_class.new("professional").to_s).to eq("professional")
    end
  end
end
