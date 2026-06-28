require "rails_helper"

RSpec.describe TenantResolver::Resolver do
  subject(:resolver) { described_class.new(tenant_repository: tenant_repository) }

  let(:tenant_repository) { instance_double(Repositories::TenantRepository) }

  let(:active_tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid,
      slug: "acme-corp",
      name: "Acme Corp",
      status: "active",
      plan: "professional",
      created_at: 2.hours.ago,
      updated_at: 1.hour.ago
    )
  end

  before do
    allow(tenant_repository).to receive(:find_by_slug).with("acme-corp").and_return(active_tenant)
    allow(tenant_repository).to receive(:find_by_slug).with(anything).and_return(nil)
  end

  describe "#resolve" do
    context "when slug is in X-Tenant-Slug header" do
      let(:request) do
        ActionDispatch::Request.new(
          "HTTP_X_TENANT_SLUG" => "acme-corp",
          "HTTP_HOST" => "api.example.com"
        )
      end

      it "returns the resolved tenant" do
        tenant = resolver.resolve(request)
        expect(tenant.slug).to eq("acme-corp")
      end
    end

    context "when slug is in subdomain" do
      let(:request) do
        ActionDispatch::Request.new(
          "HTTP_HOST" => "acme-corp.api.example.com",
          "SERVER_NAME" => "acme-corp.api.example.com"
        )
      end

      it "resolves from subdomain" do
        allow(request).to receive(:host).and_return("acme-corp.api.example.com")
        tenant = resolver.resolve(request)
        expect(tenant.slug).to eq("acme-corp")
      end
    end

    context "when header takes priority over subdomain" do
      let(:request) do
        ActionDispatch::Request.new(
          "HTTP_X_TENANT_SLUG" => "acme-corp",
          "HTTP_HOST" => "other-tenant.api.example.com"
        )
      end

      it "uses header value" do
        tenant = resolver.resolve(request)
        expect(tenant.slug).to eq("acme-corp")
      end
    end

    context "when tenant is not found" do
      let(:request) do
        ActionDispatch::Request.new("HTTP_X_TENANT_SLUG" => "nonexistent")
      end

      before do
        allow(tenant_repository).to receive(:find_by_slug).with("nonexistent").and_return(nil)
      end

      it "raises TenantNotFoundError" do
        expect { resolver.resolve(request) }
          .to raise_error(Domain::Shared::Errors::TenantNotFoundError)
      end
    end

    context "when tenant is suspended" do
      let(:suspended_tenant) do
        Domain::Tenant::Tenant.new(
          id: SecureRandom.uuid, slug: "acme-corp", name: "Acme",
          status: "suspended", plan: "free",
          created_at: 2.hours.ago, updated_at: 1.hour.ago,
          suspended_at: 1.hour.ago
        )
      end

      let(:request) do
        ActionDispatch::Request.new("HTTP_X_TENANT_SLUG" => "acme-corp")
      end

      before do
        allow(tenant_repository).to receive(:find_by_slug).with("acme-corp").and_return(suspended_tenant)
      end

      it "raises TenantSuspendedError" do
        expect { resolver.resolve(request) }
          .to raise_error(Domain::Shared::Errors::TenantSuspendedError)
      end
    end

    context "when no slug is present" do
      let(:request) do
        ActionDispatch::Request.new("HTTP_HOST" => "api.example.com")
      end

      it "raises TenantNotFoundError" do
        expect { resolver.resolve(request) }
          .to raise_error(Domain::Shared::Errors::TenantNotFoundError)
      end
    end

    context "when subdomain is a reserved word" do
      %w[www api app admin].each do |reserved|
        it "does not treat '#{reserved}' as tenant slug" do
          request = ActionDispatch::Request.new("HTTP_HOST" => "#{reserved}.api.example.com")
          allow(request).to receive(:host).and_return("#{reserved}.api.example.com")
          expect { resolver.resolve(request) }
            .to raise_error(Domain::Shared::Errors::TenantNotFoundError)
        end
      end
    end
  end
end
