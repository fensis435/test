Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

# Safelist localhost for health checks
Rack::Attack.safelist("allow localhost healthcheck") do |request|
  request.ip == "127.0.0.1" && request.path == "/healthcheck"
end

# Throttle all API requests by IP
Rack::Attack.throttle("api/ip", limit: 300, period: 5.minutes) do |request|
  request.ip if request.path.start_with?("/api/")
end

# Throttle per tenant (extracted from header)
Rack::Attack.throttle("api/tenant", limit: 1000, period: 1.minute) do |request|
  tenant_slug = request.get_header("HTTP_X_TENANT_SLUG")
  tenant_slug if tenant_slug.present? && request.path.start_with?("/api/")
end

# Strict throttle for admin endpoints
Rack::Attack.throttle("api/admin/ip", limit: 60, period: 1.minute) do |request|
  request.ip if request.path.start_with?("/api/v1/admin/")
end

# Block suspicious user agents
Rack::Attack.blocklist("block bad bots") do |request|
  request.user_agent.to_s.match?(/\A(python-requests|curl|wget)\//) &&
    !request.path.start_with?("/healthcheck")
rescue StandardError
  false
end

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"]
  now = match_data[:epoch_time]

  headers = {
    "Content-Type" => "application/json",
    "X-RateLimit-Limit" => match_data[:limit].to_s,
    "X-RateLimit-Remaining" => "0",
    "X-RateLimit-Reset" => (now + (match_data[:period] - now % match_data[:period])).to_s
  }

  body = JSON.generate({
    error: {
      code: "RATE_LIMIT_EXCEEDED",
      message: "Too many requests. Please retry after the reset time.",
      retry_after: match_data[:period] - now % match_data[:period]
    }
  })

  [429, headers, [body]]
end
