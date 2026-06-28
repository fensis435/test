module Helpers
  module AuthHelpers
    def stub_cognito_verification(payload: nil, success: true)
      verifier = instance_double(Services::Auth::CognitoJwtVerifier)
      allow(Services::Auth::CognitoJwtVerifier).to receive(:new).and_return(verifier)

      if success
        default_payload = {
          "sub" => SecureRandom.uuid,
          "email" => "test@example.com",
          "custom:tenant_slug" => "test-tenant",
          "custom:role" => "admin",
          "cognito:groups" => [],
          "token_use" => "id",
          "exp" => 1.hour.from_now.to_i,
          "iat" => Time.current.to_i
        }.merge(payload || {})

        allow(verifier).to receive(:verify).and_return(Success(default_payload))
      else
        allow(verifier).to receive(:verify).and_return(
          Failure(Domain::Shared::Errors::TokenVerificationError.new("Invalid token"))
        )
      end

      verifier
    end

    def auth_headers(tenant_slug: "test-tenant", role: "admin", sub: nil, system_admin: false)
      groups = system_admin ? ["system-admins"] : []
      payload = {
        "sub" => sub || SecureRandom.uuid,
        "email" => "user@#{tenant_slug}.example.com",
        "custom:tenant_slug" => tenant_slug,
        "custom:role" => role,
        "cognito:groups" => groups
      }
      stub_cognito_verification(payload: payload)

      { "Authorization" => "Bearer test-jwt-token", "X-Tenant-Slug" => tenant_slug }
    end

    def system_admin_headers(tenant_slug: "test-tenant")
      auth_headers(tenant_slug: tenant_slug, role: "owner", system_admin: true)
    end

    def build_current_user(sub: nil, email: nil, tenant_slug: "test-tenant", role: "admin", system_admin: false)
      Api::V1::CurrentUser.new(
        sub: sub || SecureRandom.uuid,
        email: email || "user@example.com",
        tenant_slug: tenant_slug,
        role: role,
        cognito_groups: system_admin ? ["system-admins"] : []
      )
    end
  end
end
