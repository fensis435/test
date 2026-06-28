require "rails_helper"

RSpec.describe "Api::V1::Admin::Tenants", type: :request do
  include Dry::Monads[:result]

  let(:tenant_repository) { instance_double(Repositories::TenantRepository) }
  let(:tenant_provisioner) { instance_double(Services::Tenant::TenantProvisioner) }

  let(:active_tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "active",
      plan: "professional",
      settings: { "max_users" => 100 },
      database_config: Domain::Tenant::DatabaseConfig.for_aws(
        tenant_slug: "acme-corp", rds_host: "localhost"
      ),
      created_at: 2.hours.ago,
      updated_at: 1.hour.ago
    )
  end

  let(:headers) { system_admin_headers }

  before do
    allow(Repositories::TenantRepository).to receive(:new).and_return(tenant_repository)
    allow(Services::Tenant::TenantProvisioner).to receive(:new).and_return(tenant_provisioner)
    allow(TenantResolver::TenantContext).to receive(:current_tenant).and_return(nil)

    stub_cognito_verification(payload: {
      "sub" => SecureRandom.uuid,
      "email" => "admin@system.com",
      "cognito:groups" => ["system-admins"],
      "custom:role" => "owner"
    })
  end

  describe "GET /api/v1/admin/tenants" do
    before do
      allow(tenant_repository).to receive(:find_all).and_return([active_tenant])
      allow(tenant_repository).to receive(:count).and_return(1)
    end

    it "returns 200 with tenant list" do
      get "/api/v1/admin/tenants", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "returns tenant data" do
      get "/api/v1/admin/tenants", headers: headers
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data]).to be_an(Array)
      expect(body[:data].first[:slug]).to eq("acme-corp")
    end

    it "includes pagination meta" do
      get "/api/v1/admin/tenants", headers: headers
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:meta]).to include(:total_count, :page, :per_page)
    end

    it "passes filter params to repository" do
      get "/api/v1/admin/tenants", params: { status: "active", plan: "professional" }, headers: headers
      expect(tenant_repository).to have_received(:find_all).with(
        hash_including(filters: hash_including(status: "active", plan: "professional"))
      )
    end

    context "when user is not system admin" do
      before do
        stub_cognito_verification(payload: {
          "sub" => SecureRandom.uuid,
          "email" => "regular@example.com",
          "cognito:groups" => [],
          "custom:role" => "admin"
        })
      end

      it "returns 403 Forbidden" do
        get "/api/v1/admin/tenants", headers: { "Authorization" => "Bearer token" }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/admin/tenants/:id" do
    before do
      allow(tenant_repository).to receive(:find_by_id).with(active_tenant.id).and_return(active_tenant)
      allow(tenant_repository).to receive(:find_by_slug).and_return(nil)
    end

    it "returns tenant details" do
      get "/api/v1/admin/tenants/#{active_tenant.id}", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data][:id]).to eq(active_tenant.id)
      expect(body[:data][:slug]).to eq("acme-corp")
      expect(body[:data][:status]).to eq("active")
    end

    it "does not expose sensitive settings" do
      allow(active_tenant).to receive(:settings).and_return({
        "max_users" => 100,
        "password" => "secret123"
      })
      get "/api/v1/admin/tenants/#{active_tenant.id}", headers: headers
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data][:settings]).not_to have_key(:password)
    end

    context "when tenant not found" do
      before do
        allow(tenant_repository).to receive(:find_by_id).and_return(nil)
        allow(tenant_repository).to receive(:find_by_slug).and_return(nil)
      end

      it "returns 404" do
        get "/api/v1/admin/tenants/#{SecureRandom.uuid}", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/admin/tenants" do
    let(:create_params) do
      { tenant: { slug: "new-tenant", name: "New Tenant", plan: "starter" } }
    end

    context "when provisioning succeeds" do
      let(:new_tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid,
          slug: "new-tenant",
          name: "New Tenant",
          status: "active",
          plan: "starter",
          created_at: Time.current,
          updated_at: Time.current
        )
      end

      before do
        allow(tenant_provisioner).to receive(:provision).and_return(Success(new_tenant))
      end

      it "returns 201 Created" do
        post_json "/api/v1/admin/tenants", params: create_params, headers: headers
        expect(response).to have_http_status(:created)
      end

      it "returns created tenant" do
        post_json "/api/v1/admin/tenants", params: create_params, headers: headers
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:data][:slug]).to eq("new-tenant")
      end
    end

    context "when slug is taken" do
      before do
        allow(tenant_provisioner).to receive(:provision).and_return(
          Failure(Domain::Shared::Errors::ConflictError.new("Slug already taken: new-tenant"))
        )
      end

      it "returns 409 Conflict" do
        post_json "/api/v1/admin/tenants", params: create_params, headers: headers
        expect(response).to have_http_status(:conflict)
      end
    end

    context "when validation fails" do
      before do
        allow(tenant_provisioner).to receive(:provision).and_return(
          Failure(Domain::Shared::Errors::ValidationError.new("Invalid plan"))
        )
      end

      it "returns 422 Unprocessable Entity" do
        post_json "/api/v1/admin/tenants", params: create_params, headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /api/v1/admin/tenants/:id/suspend" do
    before do
      allow(tenant_repository).to receive(:find_by_id).with(active_tenant.id).and_return(active_tenant)
      allow(tenant_repository).to receive(:find_by_slug).and_return(nil)
    end

    context "when suspension succeeds" do
      let(:suspended_tenant) do
        Domain::Tenant::Tenant.new(
          id: active_tenant.id, slug: "acme-corp", name: "Acme Corp",
          status: "suspended", plan: "professional",
          created_at: active_tenant.created_at, updated_at: Time.current,
          suspended_at: Time.current
        )
      end

      before do
        allow(tenant_provisioner).to receive(:suspend).and_return(Success(suspended_tenant))
      end

      it "returns 200 with suspended tenant" do
        post "/api/v1/admin/tenants/#{active_tenant.id}/suspend",
             params: { reason: "Non-payment" }, headers: headers
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:data][:status]).to eq("suspended")
      end
    end

    context "when state transition is invalid" do
      before do
        allow(tenant_provisioner).to receive(:suspend).and_return(
          Failure(Domain::Shared::Errors::InvalidStateTransitionError.new("Cannot suspend"))
        )
      end

      it "returns 422" do
        post "/api/v1/admin/tenants/#{active_tenant.id}/suspend", headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "POST /api/v1/admin/tenants/:id/activate" do
    let(:suspended_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "susp-t", name: "Suspended",
        status: "suspended", plan: "free",
        created_at: 2.hours.ago, updated_at: 1.hour.ago,
        suspended_at: 1.hour.ago
      )
    end

    before do
      allow(tenant_repository).to receive(:find_by_id).with(suspended_tenant.id).and_return(suspended_tenant)
      allow(tenant_repository).to receive(:find_by_slug).and_return(nil)
      allow(tenant_provisioner).to receive(:activate).and_return(
        Success(suspended_tenant.activate)
      )
    end

    it "returns 200 with activated tenant" do
      post "/api/v1/admin/tenants/#{suspended_tenant.id}/activate", headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data][:status]).to eq("active")
    end
  end

  describe "DELETE /api/v1/admin/tenants/:id" do
    before do
      allow(tenant_repository).to receive(:find_by_id).with(active_tenant.id).and_return(active_tenant)
      allow(tenant_repository).to receive(:find_by_slug).and_return(nil)
      allow(tenant_provisioner).to receive(:terminate).and_return(Success(active_tenant.terminate))
    end

    it "returns 204 No Content" do
      delete "/api/v1/admin/tenants/#{active_tenant.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "POST /api/v1/admin/tenants/:id/provision_database" do
    let(:unprovisioned_tenant) do
      Domain::Tenant::Tenant.new(
        id: SecureRandom.uuid, slug: "unprov", name: "Unprov",
        status: "provisioning", plan: "free",
        database_config: nil,
        created_at: Time.current, updated_at: Time.current
      )
    end

    before do
      allow(tenant_repository).to receive(:find_by_id).with(unprovisioned_tenant.id).and_return(unprovisioned_tenant)
      allow(tenant_repository).to receive(:find_by_slug).and_return(nil)
    end

    it "enqueues provisioning job and returns 200" do
      expect(ProvisionTenantDatabaseJob).to receive(:perform_later).with(unprovisioned_tenant.id)
      post "/api/v1/admin/tenants/#{unprovisioned_tenant.id}/provision_database", headers: headers
      expect(response).to have_http_status(:ok)
    end

    context "when database is already provisioned" do
      before do
        allow(tenant_repository).to receive(:find_by_id).and_return(active_tenant)
      end

      it "returns 409 Conflict" do
        post "/api/v1/admin/tenants/#{active_tenant.id}/provision_database", headers: headers
        expect(response).to have_http_status(:conflict)
      end
    end
  end
end
