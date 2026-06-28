module Serializers
  class TenantSerializer
    def initialize(tenant)
      @tenant = tenant
    end

    def as_json
      {
        id: @tenant.id,
        slug: @tenant.slug,
        name: @tenant.name,
        status: @tenant.status,
        plan: @tenant.plan,
        settings: sanitized_settings,
        database_provisioned: @tenant.database_provisioned?,
        created_at: @tenant.created_at&.iso8601,
        updated_at: @tenant.updated_at&.iso8601,
        suspended_at: @tenant.suspended_at&.iso8601
      }
    end

    private

    def sanitized_settings
      # Never expose internal credentials in settings
      @tenant.settings.except("suspension_reason").tap do |s|
        s.delete_if { |k, _| k.include?("password") || k.include?("secret") || k.include?("token") }
      end
    end
  end
end
