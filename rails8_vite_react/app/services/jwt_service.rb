class JwtService
  SECRET_KEY = Rails.application.credentials.secret_key_base.to_s

  def self.encode(payload, exp = 24.hours.from_now)
    payload[:exp] = exp.to_i
    payload[:iat] = Time.current.to_i
    payload[:jti] = SecureRandom.uuid # JWT ID for blacklisting
    JWT.encode(payload, SECRET_KEY)
  end

  def self.decode(token)
    decoded = JWT.decode(token, SECRET_KEY)[0]
    HashWithIndifferentAccess.new decoded
  rescue JWT::DecodeError => e
    nil
  end

  def self.encode_refresh_token(payload, exp = 7.days.from_now)
    payload[:exp] = exp.to_i
    payload[:iat] = Time.current.to_i
    payload[:type] = 'refresh'
    payload[:jti] = SecureRandom.uuid # JWT ID for blacklisting
    JWT.encode(payload, SECRET_KEY)
  end
end
