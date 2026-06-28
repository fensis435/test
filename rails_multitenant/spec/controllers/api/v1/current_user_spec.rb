require "rails_helper"

RSpec.describe Api::V1::CurrentUser do
  subject(:user) do
    described_class.new(
      sub: "sub-001",
      email: "user@example.com",
      tenant_slug: "acme-corp",
      role: role,
      cognito_groups: cognito_groups
    )
  end

  let(:role) { "member" }
  let(:cognito_groups) { [] }

  describe "#owner?" do
    context "when role is owner" do
      let(:role) { "owner" }
      it { is_expected.to be_owner }
    end

    context "when role is not owner" do
      let(:role) { "admin" }
      it { is_expected.not_to be_owner }
    end
  end

  describe "#admin?" do
    context "when role is owner" do
      let(:role) { "owner" }
      it { is_expected.to be_admin }
    end

    context "when role is admin" do
      let(:role) { "admin" }
      it { is_expected.to be_admin }
    end

    context "when role is member" do
      let(:role) { "member" }
      it { is_expected.not_to be_admin }
    end

    context "when role is viewer" do
      let(:role) { "viewer" }
      it { is_expected.not_to be_admin }
    end
  end

  describe "#system_admin?" do
    context "when in system-admins group" do
      let(:cognito_groups) { ["system-admins"] }
      it { is_expected.to be_system_admin }
    end

    context "when not in system-admins group" do
      let(:cognito_groups) { ["other-group"] }
      it { is_expected.not_to be_system_admin }
    end

    context "when groups is empty" do
      let(:cognito_groups) { [] }
      it { is_expected.not_to be_system_admin }
    end
  end

  describe "#can_manage_users?" do
    context "when admin" do
      let(:role) { "admin" }
      it { is_expected.to be_can_manage_users }
    end

    context "when member" do
      let(:role) { "member" }
      it { is_expected.not_to be_can_manage_users }
    end
  end

  describe "#==" do
    it "returns true for same sub" do
      other = described_class.new(sub: "sub-001", email: "other@example.com",
                                   tenant_slug: "other", role: "viewer")
      expect(user).to eq(other)
    end

    it "returns false for different sub" do
      other = described_class.new(sub: "sub-002", email: "user@example.com",
                                   tenant_slug: "acme-corp", role: "member")
      expect(user).not_to eq(other)
    end
  end

  describe "#to_h" do
    it "returns key fields" do
      expect(user.to_h).to include(
        sub: "sub-001",
        email: "user@example.com",
        tenant_slug: "acme-corp",
        role: "member"
      )
    end
  end
end
