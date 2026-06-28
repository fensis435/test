module Domain
  module Shared
    module Errors
      class BaseError < StandardError
        attr_reader :code, :details

        def initialize(message, code: nil, details: nil)
          super(message)
          @code = code
          @details = details
        end
      end

      class ValidationError < BaseError
        def initialize(message, details: nil)
          super(message, code: "VALIDATION_ERROR", details: details)
        end
      end

      class NotFoundError < BaseError
        def initialize(resource, identifier)
          super("#{resource} not found: #{identifier}", code: "NOT_FOUND")
        end
      end

      class UnauthorizedError < BaseError
        def initialize(message = "Unauthorized")
          super(message, code: "UNAUTHORIZED")
        end
      end

      class ForbiddenError < BaseError
        def initialize(message = "Forbidden")
          super(message, code: "FORBIDDEN")
        end
      end

      class InvalidStateTransitionError < BaseError
        def initialize(message)
          super(message, code: "INVALID_STATE_TRANSITION")
        end
      end

      class TenantNotFoundError < NotFoundError
        def initialize(identifier)
          super("Tenant", identifier)
        end
      end

      class TenantSuspendedError < BaseError
        def initialize(tenant_slug)
          super("Tenant is suspended: #{tenant_slug}", code: "TENANT_SUSPENDED")
        end
      end

      class TenantProvisioningError < BaseError
        def initialize(message)
          super(message, code: "TENANT_PROVISIONING_ERROR")
        end
      end

      class DatabaseConnectionError < BaseError
        def initialize(message)
          super(message, code: "DATABASE_CONNECTION_ERROR")
        end
      end

      class TokenVerificationError < BaseError
        def initialize(message = "Token verification failed")
          super(message, code: "TOKEN_VERIFICATION_FAILED")
        end
      end

      class TokenExpiredError < BaseError
        def initialize
          super("Token has expired", code: "TOKEN_EXPIRED")
        end
      end

      class RateLimitExceededError < BaseError
        def initialize
          super("Rate limit exceeded", code: "RATE_LIMIT_EXCEEDED")
        end
      end

      class ConflictError < BaseError
        def initialize(message)
          super(message, code: "CONFLICT")
        end
      end
    end
  end
end
