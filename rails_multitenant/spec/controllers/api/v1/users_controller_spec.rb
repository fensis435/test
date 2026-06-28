require "rails_helper"

RSpec.describe "Api::V1::Users", type: :request do
  let(:tenant) { create_domain_tenant(slug: "acme-corp") }
  let(:admin_headers) { auth_headers(tenant_slug: "acme-corp", role: "admin") }
  let(:member_headers) { auth_headers(tenant_slug: "acme-corp", role: "member") }

  before do
    set_current_tenant(tenant)
    stub_cognito_verification(payload: {
      "sub" => "admin-sub-001",
      "email" => "admin@acme-corp.example.com",
      "custom:tenant_slug" => "acme-corp",
      "custom:role" => "admin"
    })
  end

  describe "GET /api/v1/users" do
    let!(:users) { create_list(:user_record, 3) }

    it "returns 200 with user list" do
      get "/api/v1/users", headers: admin_headers
      expect(response).to have_http_status(:ok)
    end

    it "returns paginated users" do
      get "/api/v1/users", headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data]).to be_an(Array)
      expect(body[:meta]).to include(:current_page, :per_page, :total_count, :total_pages)
    end

    it "does not return deactivated users" do
      create(:user_record, :deactivated)
      get "/api/v1/users", headers: admin_headers
      body = JSON.parse(response.body, symbolize_names: true)
      returned_emails = body[:data].map { |u| u[:email] }
      expect(returned_emails).not_to include("deactivated@example.com")
    end

    context "when filtering by role" do
      let!(:admin_user) { create(:user_record, :admin) }

      it "returns only users with that role" do
        get "/api/v1/users", params: { role: "admin" }, headers: admin_headers
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:data]).to all(include(role: "admin"))
      end
    end

    context "when searching by query" do
      let!(:searchable_user) { create(:user_record, email: "searchme@example.com", display_name: "Search Me") }

      it "filters by email" do
        get "/api/v1/users", params: { q: "searchme" }, headers: admin_headers
        body = JSON.parse(response.body, symbolize_names: true)
        emails = body[:data].map { |u| u[:email] }
        expect(emails).to include("searchme@example.com")
      end
    end

    context "when unauthenticated" do
      it "returns 401" do
        get "/api/v1/users"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/v1/users/me" do
    let!(:current_user_record) { create(:user_record, cognito_sub: "admin-sub-001") }

    it "returns the current user" do
      get "/api/v1/users/me", headers: admin_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data][:cognito_sub]).to eq("admin-sub-001")
    end

    context "when the user record does not exist" do
      it "returns 404" do
        UserRecord.where(cognito_sub: "admin-sub-001").delete_all
        get "/api/v1/users/me", headers: admin_headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /api/v1/users/:id" do
    let!(:user) { create(:user_record) }

    it "returns the user" do
      get "/api/v1/users/#{user.id}", headers: admin_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:data][:id]).to eq(user.id)
    end

    context "when user not found" do
      it "returns 404" do
        get "/api/v1/users/#{SecureRandom.uuid}", headers: admin_headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/v1/users" do
    let(:valid_params) do
      {
        user: {
          cognito_sub: SecureRandom.uuid,
          email: "newuser@example.com",
          display_name: "New User",
          role: "member"
        }
      }
    end

    context "as admin" do
      it "creates the user and returns 201" do
        post_json "/api/v1/users", params: valid_params, headers: admin_headers
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:data][:email]).to eq("newuser@example.com")
      end

      it "writes an audit log entry" do
        expect {
          post_json "/api/v1/users", params: valid_params, headers: admin_headers
        }.to change(AuditLog, :count).by(1)
      end
    end

    context "as member" do
      before do
        stub_cognito_verification(payload: {
          "sub" => SecureRandom.uuid,
          "email" => "member@acme.com",
          "custom:tenant_slug" => "acme-corp",
          "custom:role" => "member"
        })
      end

      it "returns 403 Forbidden" do
        post_json "/api/v1/users", params: valid_params, headers: member_headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "with duplicate email" do
      before { create(:user_record, email: "newuser@example.com") }

      it "returns 422" do
        post_json "/api/v1/users", params: valid_params, headers: admin_headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "PATCH /api/v1/users/:id" do
    let!(:user) { create(:user_record) }

    context "as admin" do
      it "updates display_name" do
        patch_json "/api/v1/users/#{user.id}",
                   params: { user: { display_name: "Updated Name" } },
                   headers: admin_headers
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:data][:display_name]).to eq("Updated Name")
      end

      it "records audit log" do
        expect {
          patch_json "/api/v1/users/#{user.id}",
                     params: { user: { display_name: "Updated" } },
                     headers: admin_headers
        }.to change(AuditLog, :count).by(1)
      end
    end
  end

  describe "DELETE /api/v1/users/:id" do
    let!(:user) { create(:user_record) }

    context "as admin" do
      it "deactivates the user and returns 204" do
        delete "/api/v1/users/#{user.id}", headers: admin_headers
        expect(response).to have_http_status(:no_content)
        expect(user.reload.deactivated_at).not_to be_nil
      end

      it "records audit log" do
        expect {
          delete "/api/v1/users/#{user.id}", headers: admin_headers
        }.to change(AuditLog, :count).by(1)
      end
    end
  end
end
