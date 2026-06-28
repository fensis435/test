module Repositories
  class TenantRepository
    include Domain::Tenant::TenantRepositoryInterface

    def find_by_id(id)
      record = TenantRecord.find_by(id: id)
      record ? map_to_domain(record) : nil
    end

    def find_by_slug(slug)
      record = TenantRecord.find_by(slug: slug.to_s.downcase.strip)
      record ? map_to_domain(record) : nil
    end

    def find_all(page: 1, per_page: 25, filters: {})
      scope = TenantRecord.all
      scope = apply_filters(scope, filters)
      scope = scope.order(created_at: :desc)
      scope = scope.offset((page - 1) * per_page).limit(per_page)
      scope.map { |record| map_to_domain(record) }
    end

    def count(filters: {})
      scope = TenantRecord.all
      apply_filters(scope, filters).count
    end

    def save(tenant)
      record = TenantRecord.find_by(id: tenant.id) || TenantRecord.new(id: tenant.id)
      record.assign_attributes(map_to_attributes(tenant))

      if record.save
        map_to_domain(record)
      else
        raise Domain::Shared::Errors::ValidationError.new(
          "Tenant save failed",
          details: record.errors.full_messages
        )
      end
    end

    def delete(tenant)
      record = TenantRecord.find_by(id: tenant.id)
      return false unless record

      record.destroy!
      true
    end

    def exists_by_slug?(slug)
      TenantRecord.exists?(slug: slug.to_s.downcase.strip)
    end

    def count_by_status(status)
      TenantRecord.where(status: status).count
    end

    private

    def apply_filters(scope, filters)
      scope = scope.where(status: filters[:status]) if filters[:status].present?
      scope = scope.where(plan: filters[:plan]) if filters[:plan].present?
      scope = scope.search_by_name(filters[:name]) if filters[:name].present?
      scope = scope.created_after(filters[:created_after]) if filters[:created_after].present?
      scope
    end

    def map_to_domain(record)
      database_config = record.database_config.present? ? map_database_config(record.database_config) : nil

      Domain::Tenant::Tenant.new(
        id: record.id,
        slug: record.slug,
        name: record.name,
        status: record.status,
        plan: record.plan,
        settings: record.settings || {},
        database_config: database_config,
        created_at: record.created_at,
        updated_at: record.updated_at,
        suspended_at: record.suspended_at
      )
    end

    def map_database_config(config_hash)
      return nil if config_hash.blank?

      Domain::Tenant::DatabaseConfig.new(
        host: config_hash["host"],
        port: config_hash["port"] || 5432,
        database: config_hash["database"],
        username: config_hash["username"],
        schema: config_hash["schema"] || "public",
        platform: config_hash["platform"],
        endpoint_type: config_hash["endpoint_type"] || "rds",
        ssl_mode: config_hash["ssl_mode"] || "require",
        pool_size: config_hash["pool_size"] || 5
      )
    end

    def map_to_attributes(tenant)
      attrs = {
        slug: tenant.slug,
        name: tenant.name,
        status: tenant.status,
        plan: tenant.plan,
        settings: tenant.settings,
        suspended_at: tenant.suspended_at,
        updated_at: tenant.updated_at || Time.current
      }

      if tenant.database_config
        attrs[:database_config] = tenant.database_config.to_h.stringify_keys
      end

      attrs
    end
  end
end
