module TenantResolver
  class TenantContext
    CURRENT_TENANT_KEY = :current_tenant
    CURRENT_USER_KEY = :current_user

    class << self
      def current_tenant
        Thread.current[CURRENT_TENANT_KEY]
      end

      def current_tenant=(tenant)
        Thread.current[CURRENT_TENANT_KEY] = tenant
      end

      def current_user
        Thread.current[CURRENT_USER_KEY]
      end

      def current_user=(user)
        Thread.current[CURRENT_USER_KEY] = user
      end

      def set(tenant:, user: nil)
        self.current_tenant = tenant
        self.current_user = user
      end

      def clear
        Thread.current[CURRENT_TENANT_KEY] = nil
        Thread.current[CURRENT_USER_KEY] = nil
      end

      def with_tenant(tenant, user: nil)
        raise ArgumentError, "Block required" unless block_given?

        previous_tenant = current_tenant
        previous_user = current_user
        set(tenant: tenant, user: user)

        yield
      ensure
        self.current_tenant = previous_tenant
        self.current_user = previous_user
      end

      def tenant_set?
        current_tenant.present?
      end

      def require_tenant!
        return current_tenant if tenant_set?

        raise Domain::Shared::Errors::TenantNotFoundError.new("No tenant in context")
      end
    end
  end
end
