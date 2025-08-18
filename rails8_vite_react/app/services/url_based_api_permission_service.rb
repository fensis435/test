class UrlBasedApiPermissionService
  class << self
    def load_permissions_from_yaml
      @permissions_config ||= YAML.load_file(Rails.root.join('config/api_permissions.yml'))
    end

    def required_permissions_for_url(url_path, http_method)
      config = load_permissions_from_yaml
      
      # api/v1/プレフィックスを削除
      clean_path = clean_url_path(url_path)
      
      # 完全一致を最初にチェック
      permissions = config.dig('api_permissions', clean_path, http_method)
      return permissions if permissions
      
      # パラメータ付きURLとのマッチングを試行
      config['api_permissions']&.each do |pattern, methods|
        if url_matches_pattern?(clean_path, pattern) && methods[http_method]
          return methods[http_method]
        end
      end
      
      # マッチしない場合は空配列（権限不要）
      []
    end

    def user_can_access_url?(user, url_path, http_method)
      return false unless user
      
      required_permissions = required_permissions_for_url(url_path, http_method)
      return true if required_permissions.empty? # 権限設定がない場合は許可
      
      user.has_any_permission?(required_permissions)
    end

    def system_administrator_permission
      load_permissions_from_yaml["special_permissions"]["system_administrator"]
    end

    def sync_permissions_to_db
      config = load_permissions_from_yaml
      
      ActiveRecord::Base.transaction do
        # 権限の同期
        config['permissions']&.each do |name, description|
          Permission.find_or_create_by(name: name) do |permission|
            permission.description = description
          end
        end

        # URLベースAPI権限の同期
        UrlApiPermission.destroy_all # 既存データをクリア
        
        config['api_permissions']&.each do |url_pattern, methods|
          methods.each do |http_method, permission_names|
            permission_names.each do |permission_name|
              permission = Permission.find_by(name: permission_name)
              next unless permission
              
              UrlApiPermission.create!(
                url_pattern: url_pattern,
                http_method: http_method,
                permission: permission
              )
            end
          end
        end
      end
    end

    private

    def clean_url_path(url_path)
      # /api/v1/users/123 -> users/123
      # /api/v1/users -> users
      url_path.gsub(%r{^/?api/v1/?}, '').gsub(%r{^/+|/+$}, '')
    end

    def url_matches_pattern?(url_path, pattern)
      # users/123 が users/:id にマッチするかチェック
      url_regex = pattern_to_regex(pattern)
      !!(url_path =~ url_regex)
    end

    def pattern_to_regex(pattern)
      # users/:id -> /\Ausers\/[^\/]+\z/
      # users/:id/sessions -> /\Ausers\/[^\/]+\/sessions\z/
      escaped_pattern = Regexp.escape(pattern)
      regex_pattern = escaped_pattern.gsub(/\\:[\w]+/, '[^\/]+')
      Regexp.new("\\A#{regex_pattern}\\z")
    end
  end
end
