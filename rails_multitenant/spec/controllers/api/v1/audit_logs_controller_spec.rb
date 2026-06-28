require "rails_helper"

RSpec.describe "Api::V1::AuditLogs", type: :request do
  let(:tenant) { create_domain_tenant(slug: "acme-corp") }
  let(:admin_headers) { auth_headers(tenant_slug: "acme-corp", role: "admin") }
  let(:member_headers) { auth_headers(tenant_slug: "acme-corp", role: "member") }

  before do
    set_current_tenant(tenant)
    stub_cognito_verification(payload: {
      "sub" => "admin-sub-001",
      "email" => "admin@acme.com",
      "custom:tenant_slug" => "acme-corp",
      "custom:role" => "admin"
    })
  end

  describe "GET /api/v1/audit_logs" do
    let!(:log_a) { create(:audit_log, action: "user.created", occurred_at: 2.hours.ago) }
    let!(:log_b) { create(:audit_log, action: "user.updated", occurred_at: 1.hour.ago) }
    let!(:log_c) { create(:audit_log, action: "user.created", occurred_at: 30.minutes.ago) }

    it "returns 200 with audit logs" do
      get "/api/v1/audit_logs", headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it "returns paginated logs" do
      get "/api/v1/audit_logs", headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data]).to be_an(Array)
      expect(body[:meta]).to include(:current_page, :per_page, :total_count, :total_pages)
    end

    it "returns logs ordered by most recent" do
      get "/api/v1/audit_logs", headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      occurred_ats = body[:data].map { |l| l[:occurred_at] }
      expect(occurred_ats).to eq(occurred_ats.sort.reverse)
    end

    it "filters by action_filter param" do
      get "/api/v1/audit_logs", params: { action_filter: "user.created" }, headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data]).to all(include(action: "user.created"))
    end

    it "filters by actor_sub" do
      specific_log = create(:audit_log, actor_sub: "specific-actor")
      get "/api/v1/audit_logs", params: { actor_sub: "specific-actor" }, headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      ids = body[:data].map { |l| l[:id] }
      expect(ids).to include(specific_log.id)
    end

    it "filters by resource_type and resource_id" do
      resource_log = create(:audit_log, resource_type: "User", resource_id: "user-uuid-123")
      get "/api/v1/audit_logs",
          params: { resource_type: "User", resource_id: "user-uuid-123" },
          headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      ids = body[:data].map { |l| l[:id] }
      expect(ids).to include(resource_log.id)
    end

    context "when user is not admin" do
      before do
        stub_cognito_verification(payload: {
          "sub" => SecureRandom.uuid,
          "email" => "member@acme.com",
          "custom:tenant_slug" => "acme-corp",
          "custom:role" => "member"
        })
      end

      it "returns 403 Forbidden" do
        get "/api/v1/audit_logs", headers: member_headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/audit_logs/:id" do
    let!(:log) { create(:audit_log, action: "user.created") }

    it "returns the audit log" do
      get "/api/v1/audit_logs/#{log.id}", headers: admin_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data][:id]).to eq(log.id)
      expect(body[:data][:action]).to eq("user.created")
    end

    context "when log not found" do
      it "returns 404" do
        get "/api/v1/audit_logs/#{SecureRandom.uuid}", headers: admin_headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
