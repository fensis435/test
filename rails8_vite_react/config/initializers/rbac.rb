Rails.application.config.after_initialize do
  # 開発環境では起動時に権限設定を自動同期
  if Rails.env.development?
    begin
      UrlBasedApiPermissionService.sync_permissions_to_db
      Rails.logger.info "URL-based RBAC permissions synced on startup"
    rescue => e
      Rails.logger.warn "Failed to sync URL-based RBAC permissions on startup: #{e.message}"
    end
  end
end

# URL-based RBAC設定
Rails.application.config.rbac = ActiveSupport::OrderedOptions.new
Rails.application.config.rbac.permissions_file = Rails.root.join('config/api_permissions.yml')
Rails.application.config.rbac.auto_sync = Rails.env.development?
Rails.application.config.rbac.cache_permissions = Rails.env.production?
Rails.application.config.rbac.url_based = true
