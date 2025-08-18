# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

if Rails.env.development?
  puts "🌱 Seeding RBAC data..."

  # 権限設定をYAMLから同期
  UrlBasedApiPermissionService.sync_permissions_to_db
  puts "✓ Permissions synced from YAML"

  # システム管理者
  admin_user = User.find_or_create_by(email: 'admin@example.com') do |user|
    user.name = 'System Administrator'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'admin'
  end

  # 管理者権限を付与
  admin_permissions = [
    'system:admin',
    'admin:read',
    'admin:write',
    'users:admin',
    'maintenance:admin'
  ]

  admin_permissions.each do |permission|
    admin_user.add_permission(permission)
  end

  puts "✓ Admin user created: #{admin_user.email}"

  # プロジェクトマネージャー
  manager_user = User.find_or_create_by(email: 'manager@example.com') do |user|
    user.name = 'Project Manager'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'manager'
  end

  manager_permissions = [
    'manager:read',
    'manager:write',
    'users:read',
    'users:write',
    'apps:read',
    'apps:write',
    'profile:read',
    'profile:write'
  ]

  manager_permissions.each do |permission|
    manager_user.add_permission(permission)
  end

  puts "✓ Manager user created: #{manager_user.email}"

  # チームリーダー
  leader_user = User.find_or_create_by(email: 'leader@example.com') do |user|
    user.name = 'Team Leader'
    user.password = 'SecurePassword123!'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'regular'
  end

  leader_permissions = [
    'manager:read',
    'users:read',
    'apps:read',
    'apps:write',
    'profile:read',
    'profile:write'
  ]

  leader_permissions.each do |permission|
    leader_user.add_permission(permission)
  end

  puts "✓ Leader user created: #{leader_user.email}"

  # 一般開発者
  developer_user = User.find_or_create_by(email: 'developer@example.com') do |user|
    user.name = 'Developer'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'regular'
  end

  developer_permissions = [
    'profile:read',
    'profile:write',
    'apps:read',
    'apps:write'
  ]

  developer_permissions.each do |permission|
    developer_user.add_permission(permission)
  end

  puts "✓ Developer user created: #{developer_user.email}"

  # 読み取り専用ユーザー
  readonly_user = User.find_or_create_by(email: 'readonly@example.com') do |user|
    user.name = 'Readonly User'
    user.password = 'SecurePassword123!'
    user.role = 'regular'
  end

  readonly_permissions = [
    'profile:read',
    'apps:read'
  ]

  readonly_permissions.each do |permission|
    readonly_user.add_permission(permission)
  end

  puts "✓ Readonly user created: #{readonly_user.email}"

  # ゲストユーザー（最小権限）
  guest_user = User.find_or_create_by(email: 'guest@example.com') do |user|
    user.name = 'Guest User'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'regular'
  end

  guest_permissions = [
    'profile:read'
  ]

  guest_permissions.each do |permission|
    guest_user.add_permission(permission)
  end

  puts "✓ Guest user created: #{guest_user.email}"

  puts "\n📊 User Summary:"
  puts "Admin: admin@example.com (#{admin_user.permissions.count} permissions)"
  puts "Manager: manager@example.com (#{manager_user.permissions.count} permissions)"  
  puts "Leader: leader@example.com (#{leader_user.permissions.count} permissions)"
  puts "Developer: developer@example.com (#{developer_user.permissions.count} permissions)"
  puts "Readonly: readonly@example.com (#{readonly_user.permissions.count} permissions)"
  puts "Guest: guest@example.com (#{guest_user.permissions.count} permissions)"

  puts "\n🔐 Permission Summary:"
  Permission.includes(:users).each do |permission|
    puts "#{permission.name}: #{permission.users.count} users"
  end

  puts "\n🌱 RBAC seeding completed!"
end
