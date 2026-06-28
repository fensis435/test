require "rails_helper"

RSpec.describe AuditLog, type: :model do
  describe "validations" do
    subject(:log) { build(:audit_log) }

    it { is_expected.to validate_presence_of(:action) }
    it { is_expected.to validate_presence_of(:actor_sub) }
    it { is_expected.to validate_presence_of(:actor_email) }
    it { is_expected.to validate_presence_of(:tenant_id) }
  end

  describe "scopes" do
    let!(:log_a) { create(:audit_log, action: "user.created", occurred_at: 2.hours.ago) }
    let!(:log_b) { create(:audit_log, action: "user.updated", occurred_at: 1.hour.ago) }
    let!(:log_c) { create(:audit_log, action: "user.created", occurred_at: 30.minutes.ago) }

    describe ".recent" do
      it "orders by occurred_at desc" do
        ordered = described_class.recent.to_a
        expect(ordered.first.occurred_at).to be > ordered.last.occurred_at
      end
    end

    describe ".by_action" do
      it "filters by action" do
        result = described_class.by_action("user.created")
        expect(result).to include(log_a, log_c)
        expect(result).not_to include(log_b)
      end
    end

    describe ".by_resource" do
      let!(:resource_log) { create(:audit_log, resource_type: "User", resource_id: "uuid-123") }

      it "filters by resource type and id" do
        result = described_class.by_resource("User", "uuid-123")
        expect(result).to include(resource_log)
        expect(result).not_to include(log_a)
      end
    end

    describe ".by_actor" do
      let!(:actor_log) { create(:audit_log, actor_sub: "specific-actor-sub") }

      it "filters by actor sub" do
        result = described_class.by_actor("specific-actor-sub")
        expect(result).to include(actor_log)
        expect(result).not_to include(log_a)
      end
    end
  end

  describe ".record" do
    let(:tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "acme", name: "Acme",
        status: "active", plan: "free",
        created_at: Time.current, updated_at: Time.current
      )
    end

    let(:actor) do
      Api::V1::CurrentUser.new(
        sub: "actor-sub-001",
        email: "actor@acme.com",
        tenant_slug: "acme",
        role: "admin"
      )
    end

    it "creates an audit log record" do
      expect {
        described_class.record(
          tenant: tenant,
          actor: actor,
          action: "user.created",
          resource_type: "User",
          resource_id: "user-uuid",
          metadata: { email: "new@example.com" }
        )
      }.to change(described_class, :count).by(1)
    end

    it "stores all fields correctly" do
      freeze_time do
        log = described_class.record(
          tenant: tenant,
          actor: actor,
          action: "user.created",
          resource_type: "User",
          resource_id: "user-uuid",
          metadata: { email: "new@example.com" }
        )

        expect(log.tenant_id).to eq(tenant.id)
        expect(log.actor_sub).to eq("actor-sub-001")
        expect(log.actor_email).to eq("actor@acme.com")
        expect(log.actor_role).to eq("admin")
        expect(log.action).to eq("user.created")
        expect(log.resource_type).to eq("User")
        expect(log.resource_id).to eq("user-uuid")
        expect(log.metadata).to eq({ "email" => "new@example.com" })
        expect(log.occurred_at).to eq(Time.current)
      end
    end

    it "returns nil and logs error instead of raising on failure" do
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      result = described_class.record(
        tenant: tenant,
        actor: actor,
        action: "user.created"
      )
      expect(result).to be_nil
    end
  end
end
