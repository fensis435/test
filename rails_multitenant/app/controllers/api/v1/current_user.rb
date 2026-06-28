module Api
  module V1
    class CurrentUser
      SYSTEM_ADMIN_GROUP = "system-admins"

      attr_reader :sub, :email, :tenant_slug, :role, :cognito_groups

      def initialize(sub:, email:, tenant_slug:, role:, cognito_groups: [])
        @sub = sub
        @email = email
        @tenant_slug = tenant_slug
        @role = role
        @cognito_groups = Array(cognito_groups)
      end

      def owner?
        role == "owner"
      end

      def admin?
        %w[owner admin].include?(role)
      end

      def system_admin?
        cognito_groups.include?(SYSTEM_ADMIN_GROUP)
      end

      def can_manage_users?
        admin?
      end

      def can_view_audit_logs?
        admin?
      end

      def ==(other)
        other.is_a?(self.class) && sub == other.sub
      end

      def to_h
        {
          sub: sub,
          email: email,
          tenant_slug: tenant_slug,
          role: role
        }
      end
    end
  end
end
