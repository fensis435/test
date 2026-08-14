# frozen_string_literal: true

require "net/http"
require "json"
require "jwt"
require "timeout"

# ----------------------------------------------------------------------------
# Resource Server(Rails)側でのAccess Token検証。
#
# 最優先要件を反映し、Cognito固有の検証ロジック(cognito:groupsクレームの
# 読み替え等)はここには一切書かない。標準OIDCの手続き
# (Discovery → JWKS取得 → kidで鍵特定 → RS256署名検証 → iss/exp検証)
# のみで完結させる。将来Cognito固有のクレーム変換が必要になった場合は、
# このクラスの外側(呼び出し元、あるいは専用のCognito Compat層)に
# 実装を閉じ込めること。
#
# JWKSはDiscoveryドキュメントのjwks_uriから取得し、鍵ローテーションに
# 追従できるよう簡易キャッシュ(TTL付き・kid未検出時は強制再取得)を持つ。
# ----------------------------------------------------------------------------

class TokenVerifier
  class Error < StandardError; end
  class TokenExpiredError < Error; end
  class InvalidTokenError < Error; end

  JWKS_CACHE_TTL = 5 * 60 # 秒

  def initialize(issuer: Rails.application.config.x.oidc.issuer)
    @issuer = issuer.to_s.chomp("/")
  end

  # @param token [String] Authorizationヘッダから取り出したBearerトークン
  # @return [Hash] 検証済みのJWTクレーム
  # @raise [TokenVerifier::Error] 検証に失敗した場合
  def verify!(token)
    raise InvalidTokenError, "token is blank" if token.to_s.strip.empty?

    payload, = JWT.decode(
      token,
      nil,
      true,
      algorithms: ["RS256"],
      jwks: jwks_loader,
      verify_iss: true,
      iss: @issuer
    )

    payload
  rescue JWT::ExpiredSignature
    raise TokenExpiredError, "access token has expired"
  rescue JWT::DecodeError => e
    raise InvalidTokenError, "token verification failed: #{e.message}"
  end

  private

  def jwks_loader
    lambda do |options|
      JWT::JWK::Set.new(fetch_jwks(force_refresh: options[:kid_not_found] == true))
    end
  end

  def fetch_jwks(force_refresh: false)
    @jwks_cache = nil if force_refresh || jwks_cache_expired?
    @jwks_cache ||= begin
      @jwks_fetched_at = Time.now
      fetch_json(discovery_document.fetch("jwks_uri"))
    end
  end

  def jwks_cache_expired?
    @jwks_fetched_at.nil? || (Time.now - @jwks_fetched_at) > JWKS_CACHE_TTL
  end

  def discovery_document
    @discovery_document ||= fetch_json("#{@issuer}/.well-known/openid-configuration")
  end

  def fetch_json(url)
    uri = URI.parse(url)
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise Error, "GET #{url} failed: #{response.code}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "GET #{url} returned invalid JSON: #{e.message}"
  rescue Errno::ECONNREFUSED, SocketError, Timeout::Error => e
    raise Error, "Failed to reach OIDC issuer (#{e.class}): #{url}. " \
                 "oidc-dev-server が起動しているか確認してください。"
  end
end
