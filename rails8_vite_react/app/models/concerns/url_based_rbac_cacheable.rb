module UrlBasedRbacCacheable
  extend ActiveSupport::Concern

  included do
    if Rails.application.config.rbac.cache_permissions
      after_commit :clear_url_permission_cache
    end
  end

  def url_permission_cache_key(url_path, http_method)
    "user_url_permissions_#{id}_#{url_path.gsub('/', '_')}_#{http_method}_#{updated_at.to_i}"
  end

  def cached_permissions
    return permissions unless Rails.application.config.rbac.cache_permissions
    
    Rails.cache.fetch("user_permissions_#{id}_#{updated_at.to_i}", expires_in: 1.hour) do
      permissions.pluck(:name)
    end
  end

  def cached_can_access_url?(url_path, http_method)
    return can_access_url?(url_path, http_method) unless Rails.application.config.rbac.cache_permissions
    
    cache_key = url_permission_cache_key(url_path, http_method)
    
    Rails.cache.fetch(cache_key, expires_in: 30.minutes) do
      can_access_url?(url_path, http_method)
    end
  end

  # URL-based権限パターンのキャッシュ
  def self.cached_required_permissions_for_url(url_path, http_method)
    return UrlBasedApiPermissionService.required_permissions_for_url(url_path, http_method) unless Rails.application.config.rbac.cache_permissions
    
    cache_key = "url_required_permissions_#{url_path.gsub('/', '_')}_#{http_method}"
    
    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      UrlBasedApiPermissionService.required_permissions_for_url(url_path, http_method)
    end
  end

  private

  def clear_url_permission_cache
    return unless Rails.application.config.rbac.cache_permissions
    
    Rails.cache.delete_matched("user_permissions_#{id}_*")
    Rails.cache.delete_matched("user_url_permissions_#{id}_*")
  end
end

# UrlBasedApiPermissionServiceにキャッシュ機能追加
class UrlBasedApiPermissionService
  class << self
    def required_permissions_for_url_cached(url_path, http_method)
      if Rails.application.config.rbac.cache_permissions
        UrlBasedRbacCacheable.cached_required_permissions_for_url(url_path, http_method)
      else
        required_permissions_for_url(url_path, http_method)
      end
    end
  end
end
