require "rails_helper"

RSpec.describe TenantIsolationMiddleware do
  let(:app) { ->(env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] } }
  let(:tenant_resolver) { instance_double(TenantResolver::Resolver) }
  let(:middleware) { described_class.new(app, tenant_resolver: tenant_resolver) }

  let(:active_tenant) do
    Domain::Tenant::Tenant.new(
      id: SecureRandom.uuid, slug: "acme-corp", name: "Acme Corp",
      status: "active", plan: "professional",
      created_at: 2.hours.ago, updated_at: 1.hour.ago
    )
  end

  def build_env(path: "/api/v1/users", headers: {})
    Rack::MockRequest.env_for(path, headers)
  end

  after { TenantResolver::TenantContext.clear }

  describe "#call" do
    context "when path is in skip list" do
      it "skips tenant resolution for /healthcheck" do
        env = build_env(path: "/healthcheck")
        status, = middleware.call(env)
        expect(tenant_resolver).not_to have_received(:resolve) rescue nil
        expect(status).to eq(200)
      end

      it "skips tenant resolution for /up" do
        env = build_env(path: "/up")
        status, = middleware.call(env)
        expect(status).to eq(200)
      end
    end

    context "when tenant resolution succeeds" do
      before do
        allow(tenant_resolver).to receive(:resolve).and_return(active_tenant)
      end

      it "calls the next app" do
        env = build_env
        status, = middleware.call(env)
        expect(status).to eq(200)
      end

      it "sets tenant in env" do
        captured_env = nil
        capturing_app = ->(env) { captured_env = env; [200, {}, [""]] }
        mw = described_class.new(capturing_app, tenant_resolver: tenant_resolver)
        mw.call(build_env)
        expect(captured_env["multitenant.tenant"]).to eq(active_tenant)
        expect(captured_env["multitenant.tenant_slug"]).to eq("acme-corp")
      end

      it "sets tenant context on thread" do
        captured_tenant = nil
        capturing_app = ->(env) {
          captured_tenant = TenantResolver::TenantContext.current_tenant
          [200, {}, [""]]
        }
        mw = described_class.new(capturing_app, tenant_resolver: tenant_resolver)
        mw.call(build_env)
        expect(captured_tenant).to eq(active_tenant)
      end

      it "clears tenant context after request" do
        middleware.call(build_env)
        expect(TenantResolver::TenantContext.current_tenant).to be_nil
      end

      it "clears tenant context even when app raises" do
        raising_app = ->(_env) { raise "boom" }
        mw = described_class.new(raising_app, tenant_resolver: tenant_resolver)
        expect { mw.call(build_env) }.to raise_error("boom")
        expect(TenantResolver::TenantContext.current_tenant).to be_nil
      end
    end

    context "when tenant is not found" do
      before do
        allow(tenant_resolver).to receive(:resolve)
          .and_raise(Domain::Shared::Errors::TenantNotFoundError.new("unknown"))
      end

      it "returns 404" do
        status, headers, body = middleware.call(build_env)
        expect(status).to eq(404)
        expect(headers["Content-Type"]).to eq("application/json")
        parsed = JSON.parse(body.join)
        expect(parsed["error"]["code"]).to eq("TENANT_NOT_FOUND")
      end
    end

    context "when tenant is suspended" do
      before do
        allow(tenant_resolver).to receive(:resolve)
          .and_raise(Domain::Shared::Errors::TenantSuspendedError.new("acme-corp"))
      end

      it "returns 403" do
        status, _headers, body = middleware.call(build_env)
        expect(status).to eq(403)
        parsed = JSON.parse(body.join)
        expect(parsed["error"]["code"]).to eq("TENANT_SUSPENDED")
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(tenant_resolver).to receive(:resolve).and_raise(StandardError, "unexpected")
      end

      it "returns 500" do
        status, _headers, body = middleware.call(build_env)
        expect(status).to eq(500)
        parsed = JSON.parse(body.join)
        expect(parsed["error"]["code"]).to eq("INTERNAL_ERROR")
      end
    end
  end
end
