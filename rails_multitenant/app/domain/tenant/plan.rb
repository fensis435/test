module Domain
  module Tenant
    class Plan
      VALID_PLANS = %w[free starter professional enterprise].freeze

      PLAN_LIMITS = {
        "free" => {
          max_users: 5,
          storage_gb: 1,
          api_rate_limit: 100,
          custom_domain: false,
          sso_enabled: false,
          audit_log_days: 7
        },
        "starter" => {
          max_users: 25,
          storage_gb: 10,
          api_rate_limit: 500,
          custom_domain: false,
          sso_enabled: false,
          audit_log_days: 30
        },
        "professional" => {
          max_users: 100,
          storage_gb: 100,
          api_rate_limit: 2000,
          custom_domain: true,
          sso_enabled: true,
          audit_log_days: 90
        },
        "enterprise" => {
          max_users: Float::INFINITY,
          storage_gb: Float::INFINITY,
          api_rate_limit: 10_000,
          custom_domain: true,
          sso_enabled: true,
          audit_log_days: 365
        }
      }.freeze

      attr_reader :name

      def initialize(name)
        raise Domain::Shared::Errors::ValidationError, "Invalid plan: #{name}" unless VALID_PLANS.include?(name)

        @name = name
      end

      def limits
        PLAN_LIMITS[name]
      end

      def max_users
        limits[:max_users]
      end

      def storage_gb
        limits[:storage_gb]
      end

      def api_rate_limit
        limits[:api_rate_limit]
      end

      def sso_enabled?
        limits[:sso_enabled]
      end

      def custom_domain?
        limits[:custom_domain]
      end

      def audit_log_days
        limits[:audit_log_days]
      end

      def enterprise?
        name == "enterprise"
      end

      def upgradeable_to?(target_plan)
        VALID_PLANS.index(target_plan) > VALID_PLANS.index(name)
      end

      def ==(other)
        other.is_a?(self.class) && name == other.name
      end

      def to_s
        name
      end
    end
  end
end
