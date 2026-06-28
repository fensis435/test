class TenantIsolationMiddleware
  SKIP_PATHS = %w[/healthcheck /up /api/v1/admin/tenants].freeze
  ADMIN_PATHS = %w[/api/v1/admin/].freeze

  def initialize(app, tenant_resolver: nil, logger: Rails.logger)
    @app = app
    @tenant_resolver = tenant_resolver || TenantResolver::Resolver.new
    @logger = logger
  end

  def call(env)
    request = ActionDispatch::Request.new(env)

    if skip_tenant_resolution?(request)
      return @app.call(env)
    end

    resolve_and_set_tenant(env, request)
  ensure
    TenantResolver::TenantContext.clear
  end

  private

  def skip_tenant_resolution?(request)
    SKIP_PATHS.any? { |path| request.path.start_with?(path) }
  end

  def resolve_and_set_tenant(env, request)
    tenant = @tenant_resolver.resolve(request)

    TenantResolver::TenantContext.set(tenant: tenant)
    env["multitenant.tenant"] = tenant
    env["multitenant.tenant_slug"] = tenant.slug

    @logger.tagged("tenant:#{tenant.slug}") do
      @app.call(env)
    end
  rescue Domain::Shared::Errors::TenantNotFoundError => e
    render_error(404, "TENANT_NOT_FOUND", e.message)
  rescue Domain::Shared::Errors::TenantSuspendedError => e
    render_error(403, "TENANT_SUSPENDED", e.message)
  rescue StandardError => e
    @logger.error("TenantIsolationMiddleware error: #{e.class} - #{e.message}")
    render_error(500, "INTERNAL_ERROR", "Internal server error")
  end

  def render_error(status, code, message)
    body = JSON.generate({
      error: {
        code: code,
        message: message
      }
    })

    [
      status,
      { "Content-Type" => "application/json", "Content-Length" => body.bytesize.to_s },
      [body]
    ]
  end
end
