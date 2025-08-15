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
  # 管理者ユーザーの作成
  admin_user = User.find_or_create_by(email: 'admin@example.com') do |user|
    user.name = 'Admin User'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'admin'
  end

  # 一般ユーザーの作成
  test_user = User.find_or_create_by(email: 'test@example.com') do |user|
    user.name = 'Test User'
    user.password = 'password123'
    user.password_confirmation = 'password123'
    user.role = 'regular'
  end

  puts "Created users:"
  puts "Admin: admin@example.com / password123 / admin"
  puts "Test: test@example.com / password123 / regular"
end
