namespace :tokens do
  desc 'Cleanup expired blacklisted tokens'
  task cleanup: :environment do
    count = BlacklistedToken.cleanup_expired
    puts "Cleaned up #{count} expired tokens"
  end
end
