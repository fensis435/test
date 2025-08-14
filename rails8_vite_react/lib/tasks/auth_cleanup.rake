namespace :auth do
  desc "Clean up expired tokens and sessions"
  task cleanup: :environment do
    puts "Cleaning up expired tokens and sessions..."
    
    expired_tokens = BlacklistedToken.expired.count
    expired_sessions = UserSession.expired.count
    
    TokenBlacklistService.cleanup_expired_tokens
    
    puts "Cleaned up #{expired_tokens} expired blacklisted tokens"
    puts "Cleaned up #{expired_sessions} expired sessions"
    puts "Cleanup completed!"
  end
end
