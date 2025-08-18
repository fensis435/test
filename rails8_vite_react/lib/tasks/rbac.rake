namespace :rbac do
  desc "Initialize RBAC system from YAML configuration"
  task initialize: :environment do
    puts "Initializing URL-based RBAC system..."
    
    UrlBasedApiPermissionService.sync_permissions_to_db
    puts "✓ URL-based permissions synced from YAML to database"
    
    # デモユーザーの作成（開発環境のみ）
    if Rails.env.development?
      create_demo_users
      puts "✓ Demo users created"
    end
    
    puts "URL-based RBAC system initialization completed!"
  end

  desc "Sync permissions from YAML to database"
  task sync: :environment do
    puts "Syncing URL-based permissions from YAML..."
    UrlBasedApiPermissionService.sync_permissions_to_db
    puts "✓ URL-based permissions synced successfully"
  end

  desc "Test URL permission matching"
  task :test_url_matching, [:url, :method] => :environment do |t, args|
    if args[:url].blank? || args[:method].blank?
      puts "Usage: rake rbac:test_url_matching[users/123,GET]"
      exit 1
    end
    
    required_permissions = UrlBasedApiPermissionService.required_permissions_for_url(args[:url], args[:method])
    
    puts "\nURL Pattern Matching Test:"
    puts "URL: #{args[:url]}"
    puts "Method: #{args[:method]}"
    puts "Required Permissions: #{required_permissions.any? ? required_permissions.join(', ') : 'None (public access)'}"
    
    # すべてのパターンとのマッチング結果を表示
    puts "\nAll Pattern Matches:"
    config = UrlBasedApiPermissionService.load_permissions_from_yaml
    config['api_permissions']&.each do |pattern, methods|
      if methods[args[:method]]
        matches = url_matches_pattern_debug?(args[:url], pattern)
        status = matches ? "✓" : "✗"
        puts "  #{status} #{pattern} -> #{methods[args[:method]].join(', ')}"
      end
    end
  end

  desc "Show user URL access rights"
  task :show_url_access, [:email] => :environment do |t, args|
    if args[:email].blank?
      puts "Usage: rake rbac:show_url_access[user@example.com]"
      exit 1
    end
    
    user = User.find_by(email: args[:email])
    unless user
      puts "User not found: #{args[:email]}"
      exit 1
    end
    
    puts "\nUser: #{user.name} (#{user.email})"
    puts "Legacy Role: #{user.role}"
    puts "Permissions:"
    
    if user.permissions.any?
      user.permissions.order(:name).each do |permission|
        puts "  - #{permission.name}: #{permission.description}"
      end
    else
      puts "  No permissions assigned"
    end
    
    puts "\nURL Access Rights:"
    check_url_access_for_user(user)
  end

  desc "Test user access to specific URL"
  task :test_user_access, [:email, :url, :method] => :environment do |t, args|
    if args[:email].blank? || args[:url].blank? || args[:method].blank?
      puts "Usage: rake rbac:test_user_access[user@example.com,users/123,GET]"
      exit 1
    end
    
    user = User.find_by(email: args[:email])
    unless user
      puts "User not found: #{args[:email]}"
      exit 1
    end
    
    can_access = user.can_access_url?(args[:url], args[:method])
    required_permissions = UrlBasedApiPermissionService.required_permissions_for_url(args[:url], args[:method])
    user_permissions = user.permissions.pluck(:name)
    
    puts "\nAccess Test Result:"
    puts "User: #{user.email}"
    puts "URL: #{args[:url]}"
    puts "Method: #{args[:method]}"
    puts "Can Access: #{can_access ? 'YES ✓' : 'NO ✗'}"
    puts "Required Permissions: #{required_permissions.any? ? required_permissions.join(', ') : 'None'}"
    puts "User Permissions: #{user_permissions.any? ? user_permissions.join(', ') : 'None'}"
    
    if !can_access && required_permissions.any?
      missing = required_permissions - user_permissions
      puts "Missing Permissions: #{missing.join(', ')}"
    end
  end

  desc "List all URL patterns and their permissions"
  task list_url_patterns: :environment do
    puts "\nURL-based Permission Patterns:"
    puts "=" * 60
    
    config = UrlBasedApiPermissionService.load_permissions_from_yaml
    config['api_permissions']&.each do |url_pattern, methods|
      puts "\n#{url_pattern}:"
      methods.each do |http_method, permissions|
        perm_str = permissions.any? ? permissions.join(', ') : '(public)'
        puts "  #{http_method.ljust(7)} -> #{perm_str}"
      end
    end
  end

  desc "Migrate legacy roles to RBAC permissions"
  task migrate_legacy_roles: :environment do
    puts "Migrating legacy roles to URL-based RBAC permissions..."
    
    User.transaction do
      User.find_each do |user|
        next if user.permissions.any? # 既に権限が設定されている場合はスキップ
        
        legacy_permissions = user.legacy_role_permissions
        legacy_permissions.each do |permission_name|
          user.add_permission(permission_name)
        end
        
        puts "✓ Migrated user #{user.email}: #{legacy_permissions.join(', ')}"
      end
    end
    
    puts "Legacy role migration completed!"
  end

  desc "Add permission to user"
  task :add_permission, [:email, :permission] => :environment do |t, args|
    if args[:email].blank? || args[:permission].blank?
      puts "Usage: rake rbac:add_permission[user@example.com,manager:read]"
      exit 1
    end
    
    user = User.find_by(email: args[:email])
    unless user
      puts "User not found: #{args[:email]}"
      exit 1
    end
    
    if user.add_permission(args[:permission])
      puts "✓ Permission '#{args[:permission]}' added to #{user.email}"
    else
      puts "✗ Failed to add permission '#{args[:permission]}' to #{user.email}"
      puts "   Make sure the permission exists in the database"
    end
  end

  desc "Remove permission from user"
  task :remove_permission, [:email, :permission] => :environment do |t, args|
    if args[:email].blank? || args[:permission].blank?
      puts "Usage: rake rbac:remove_permission[user@example.com,manager:read]"
      exit 1
    end
    
    user = User.find_by(email: args[:email])
    unless user
      puts "User not found: #{args[:email]}"
      exit 1
    end
    
    if user.remove_permission(args[:permission])
      puts "✓ Permission '#{args[:permission]}' removed from #{user.email}"
    else
      puts "✗ Failed to remove permission '#{args[:permission]}' from #{user.email}"
    end
  end

  private

  def create_demo_users
    # 管理者ユーザー
    admin = User.find_or_create_by(email: 'admin@example.com') do |user|
      user.name = 'Admin User'
      user.password = 'password123'
      user.role = 'admin' # legacy role
    end
    admin.add_permission('system:admin')
    admin.add_permission('admin:read')
    admin.add_permission('admin:write')
    
    # マネージャーユーザー
    manager = User.find_or_create_by(email: 'manager@example.com') do |user|
      user.name = 'Manager User'
      user.password = 'password123'
      user.role = 'manager' # legacy role
    end
    manager.add_permission('manager:read')
    manager.add_permission('manager:write')
    manager.add_permission('users:read')
    manager.add_permission('users:write')
    
    # 一般ユーザー
    regular = User.find_or_create_by(email: 'user@example.com') do |user|
      user.name = 'Regular User'
      user.password = 'password123'
      user.role = 'regular' # legacy role
    end
    regular.add_permission('profile:read')
    regular.add_permission('profile:write')
  end

  def check_url_access_for_user(user)
    config = UrlBasedApiPermissionService.load_permissions_from_yaml
    
    config['api_permissions']&.each do |url_pattern, methods|
      puts "\n#{url_pattern}:"
      methods.each do |http_method, required_permissions|
        can_access = required_permissions.empty? || 
                    user.has_any_permission?(required_permissions)
        status = can_access ? "✓" : "✗"
        perm_str = required_permissions.any? ? required_permissions.join(', ') : '(public)'
        puts "  #{status} #{http_method.ljust(7)} -> #{perm_str}"
      end
    end
  end

  def url_matches_pattern_debug?(url_path, pattern)
    # users/123 が users/:id にマッチするかチェック（デバッグ用）
    escaped_pattern = Regexp.escape(pattern)
    regex_pattern = escaped_pattern.gsub(/\\:[\w]+/, '[^\/]+')
    regex = Regexp.new("\\A#{regex_pattern}\\z")
    !!(url_path =~ regex)
  end
end
