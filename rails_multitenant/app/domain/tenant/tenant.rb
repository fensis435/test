module Domain
  module Tenant
    class Tenant
      include Dry::Monads[:result]

      VALID_STATUSES = %w[provisioning active suspended terminated].freeze
      SLUG_FORMAT = /\A[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]\z/

      attr_reader :id, :slug, :name, :status, :plan, :settings,
                  :database_config, :created_at, :updated_at, :suspended_at

      def initialize(
        id:,
        slug:,
        name:,
        status:,
        plan:,
        settings: {},
        database_config: nil,
        created_at: nil,
        updated_at: nil,
        suspended_at: nil
      )
        @id = id
        @slug = slug
        @name = name
        @status = status
        @plan = plan
        @settings = settings
        @database_config = database_config
        @created_at = created_at
        @updated_at = updated_at
        @suspended_at = suspended_at
      end

      def self.create(slug:, name:, plan:, settings: {})
        validate_slug!(slug)
        validate_name!(name)
        validate_plan!(plan)

        new(
          id: SecureRandom.uuid,
          slug: slug.downcase.strip,
          name: name.strip,
          status: "provisioning",
          plan: plan,
          settings: default_settings.merge(settings),
          created_at: Time.current,
          updated_at: Time.current
        )
      end

      def activate
        raise Domain::Shared::Errors::InvalidStateTransitionError,
              "Cannot activate tenant in status: #{status}" unless can_activate?

        self.class.new(
          id: id,
          slug: slug,
          name: name,
          status: "active",
          plan: plan,
          settings: settings,
          database_config: database_config,
          created_at: created_at,
          updated_at: Time.current,
          suspended_at: nil
        )
      end

      def suspend(reason: nil)
        raise Domain::Shared::Errors::InvalidStateTransitionError,
              "Cannot suspend tenant in status: #{status}" unless can_suspend?

        new_settings = settings.merge("suspension_reason" => reason).compact
        self.class.new(
          id: id,
          slug: slug,
          name: name,
          status: "suspended",
          plan: plan,
          settings: new_settings,
          database_config: database_config,
          created_at: created_at,
          updated_at: Time.current,
          suspended_at: Time.current
        )
      end

      def terminate
        raise Domain::Shared::Errors::InvalidStateTransitionError,
              "Cannot terminate tenant in status: #{status}" unless can_terminate?

        self.class.new(
          id: id,
          slug: slug,
          name: name,
          status: "terminated",
          plan: plan,
          settings: settings,
          database_config: database_config,
          created_at: created_at,
          updated_at: Time.current,
          suspended_at: suspended_at
        )
      end

      def assign_database_config(config)
        self.class.new(
          id: id,
          slug: slug,
          name: name,
          status: status,
          plan: plan,
          settings: settings,
          database_config: config,
          created_at: created_at,
          updated_at: Time.current,
          suspended_at: suspended_at
        )
      end

      def active?
        status == "active"
      end

      def suspended?
        status == "suspended"
      end

      def provisioning?
        status == "provisioning"
      end

      def terminated?
        status == "terminated"
      end

      def can_activate?
        %w[provisioning suspended].include?(status)
      end

      def can_suspend?
        status == "active"
      end

      def can_terminate?
        %w[active suspended provisioning].include?(status)
      end

      def database_provisioned?
        database_config.present?
      end

      def schema_name
        "tenant_#{slug.gsub("-", "_")}"
      end

      def ==(other)
        other.is_a?(self.class) && id == other.id
      end

      def to_h
        {
          id: id,
          slug: slug,
          name: name,
          status: status,
          plan: plan,
          settings: settings,
          database_config: database_config,
          created_at: created_at,
          updated_at: updated_at,
          suspended_at: suspended_at
        }
      end

      private

      def self.validate_slug!(slug)
        raise Domain::Shared::Errors::ValidationError, "Slug is required" if slug.blank?
        raise Domain::Shared::Errors::ValidationError, "Slug format is invalid" unless slug.match?(SLUG_FORMAT)
      end

      def self.validate_name!(name)
        raise Domain::Shared::Errors::ValidationError, "Name is required" if name.blank?
        raise Domain::Shared::Errors::ValidationError, "Name is too long (max 255)" if name.length > 255
      end

      def self.validate_plan!(plan)
        valid_plans = Domain::Tenant::Plan::VALID_PLANS
        raise Domain::Shared::Errors::ValidationError, "Invalid plan: #{plan}" unless valid_plans.include?(plan)
      end

      def self.default_settings
        {
          "max_users" => 100,
          "storage_gb" => 10,
          "api_rate_limit" => 1000,
          "mfa_required" => false
        }
      end
    end
  end
end
