require "rails_helper"

RSpec.describe UserRecord, type: :model do
  describe "validations" do
    subject(:user) { build(:user_record) }

    it { is_expected.to validate_presence_of(:cognito_sub) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_inclusion_of(:role).in_array(described_class::VALID_ROLES) }

    context "email uniqueness" do
      before { create(:user_record, email: "taken@example.com") }

      it "rejects duplicate email" do
        user.email = "taken@example.com"
        expect(user).not_to be_valid
        expect(user.errors[:email]).to include("has already been taken")
      end

      it "is case-insensitive" do
        user.email = "TAKEN@example.com"
        expect(user).not_to be_valid
      end
    end

    context "cognito_sub uniqueness" do
      before { create(:user_record, cognito_sub: "existing-sub") }

      it "rejects duplicate cognito_sub" do
        user.cognito_sub = "existing-sub"
        expect(user).not_to be_valid
      end
    end

    context "email format" do
      it "accepts valid email" do
        user.email = "valid.email+tag@example.co.jp"
        expect(user).to be_valid
      end

      it "rejects invalid email format" do
        user.email = "not-an-email"
        expect(user).not_to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active_user)  { create(:user_record) }
    let!(:deactivated)  { create(:user_record, :deactivated) }
    let!(:admin_user)   { create(:user_record, :admin) }
    let!(:viewer_user)  { create(:user_record, :viewer) }

    describe ".active" do
      it "returns only non-deactivated users" do
        expect(described_class.active).to include(active_user, admin_user, viewer_user)
        expect(described_class.active).not_to include(deactivated)
      end
    end

    describe ".by_role" do
      it "filters by role" do
        expect(described_class.by_role("admin")).to include(admin_user)
        expect(described_class.by_role("admin")).not_to include(active_user, viewer_user)
      end
    end

    describe ".search" do
      let!(:searchable) { create(:user_record, email: "findme@example.com", display_name: "Find Me") }

      it "searches by email (case-insensitive)" do
        expect(described_class.search("findme")).to include(searchable)
        expect(described_class.search("FINDME")).to include(searchable)
      end

      it "searches by display_name (case-insensitive)" do
        expect(described_class.search("Find Me")).to include(searchable)
        expect(described_class.search("find me")).to include(searchable)
      end

      it "does not return unmatched records" do
        expect(described_class.search("nobody")).not_to include(searchable)
      end
    end
  end

  describe "#active?" do
    it "returns true when deactivated_at is nil" do
      user = build(:user_record)
      expect(user.active?).to be(true)
    end

    it "returns false when deactivated_at is set" do
      user = build(:user_record, :deactivated)
      expect(user.active?).to be(false)
    end
  end

  describe "#deactivate!" do
    let!(:user) { create(:user_record) }

    it "sets deactivated_at to now" do
      freeze_time do
        user.deactivate!
        expect(user.deactivated_at).to eq(Time.current)
      end
    end

    it "persists the change" do
      user.deactivate!
      expect(user.reload.deactivated_at).not_to be_nil
    end
  end
end
