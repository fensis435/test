module TenantResolver
  class Resolver
    TENANT_HEADER = "X-Tenant-Slug"
    TENANT_SUBDOMAIN_REGEX = /\A([a-z0-9][a-z0-9\-]{1,61}[a-z0-9])\./.freeze

    def initialize(
      tenant_repository: nil,
      logger: Rails.logger
    )
      @tenant_repository = tenant_repository || Repositories::TenantRepository.new
      @logger = logger
    end

    # Resolve tenant from request
    # @param request [ActionDispatch::Request]
    # @return [Domain::Tenant::Tenant]
    # @raise [Domain::Shared::Errors::TenantNotFoundError]
    def resolve(request)
      slug = extract_slug(request)
      raise Domain::Shared::Errors::TenantNotFoundError.new(slug || "unknown") if slug.blank?

      tenant = @tenant_repository.find_by_slug(slug)
      raise Domain::Shared::Errors::TenantNotFoundError.new(slug) if tenant.nil?
      raise Domain::Shared::Errors::TenantSuspendedError.new(slug) if tenant.suspended?

      @logger.debug("Resolved tenant: #{tenant.slug} (#{tenant.id})")
      tenant
    end

    private

    def extract_slug(request)
      # Priority: Header > Subdomain > JWT claim
      from_header(request) ||
        from_subdomain(request) ||
        from_jwt_claim(request)
    end

    def from_header(request)
      header_value = request.headers[TENANT_HEADER]
      return nil if header_value.blank?

      header_value.to_s.downcase.strip
    end

    def from_subdomain(request)
      host = request.host
      match = host.match(TENANT_SUBDOMAIN_REGEX)
      return nil unless match

      subdomain = match[1]
      return nil if %w[www api app admin].include?(subdomain)

      subdomain
    end

    def from_jwt_claim(request)
      auth_header = request.headers["Authorization"]
      return nil if auth_header.blank?

      token = auth_header.sub(/\ABearer\s+/i, "")
      return nil if token.blank?

      # Decode without verification here (verification happens in auth middleware)
      payload = JWT.decode(token, nil, false).first
      payload["custom:tenant_slug"] || payload["tenant_slug"]
    rescue JWT::DecodeError
      nil
    end
  end
end
