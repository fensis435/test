# =============================================================================
# config/initializers/cognito_jwt.rb
# Cognito JWT 認証設定 (JWKS による公開鍵検証)
# =============================================================================
require 'jwt'
require 'net/http'
require 'json'

module CognitoJwt
  class Verifier
    JWKS_CACHE_TTL = 3600  # 1時間キャッシュ

    def initialize
      @user_pool_id   = ENV.fetch('COGNITO_USER_POOL_ID')
      @client_id      = ENV.fetch('COGNITO_CLIENT_ID')
      @region         = ENV.fetch('AWS_REGION', 'ap-northeast-1')
      @issuer         = ENV.fetch('COGNITO_ISSUER',
                          "https://cognito-idp.#{@region}.amazonaws.com/#{@user_pool_id}")
      @jwks_uri       = ENV.fetch('COGNITO_JWKS_URI',
                          "#{@issuer}/.well-known/jwks.json")
      @jwks_cache     = nil
      @jwks_cached_at = nil
    end

    # JWT トークンを検証し、ペイロードを返す
    # @param token [String] Bearer トークン
    # @return [Hash] デコード済みペイロード
    # @raise [JWT::DecodeError] 検証失敗時
    def verify!(token)
      jwks = fetch_jwks

      # RS256 で検証 (Cognito はRS256を使用)
      decoded = JWT.decode(
        token,
        nil,
        true,
        algorithms:        ['RS256'],
        jwks:              { keys: jwks['keys'] },
        iss:               @issuer,
        verify_iss:        true,
        aud:               @client_id,
        verify_aud:        true,
        verify_expiration: true
      )

      payload = decoded.first

      # token_use の確認 (id または access)
      unless %w[id access].include?(payload['token_use'])
        raise JWT::InvalidPayload, "Invalid token_use: #{payload['token_use']}"
      end

      payload
    end

    private

    def fetch_jwks
      # キャッシュ有効時はキャッシュを返す
      if @jwks_cache && @jwks_cached_at && (Time.now - @jwks_cached_at) < JWKS_CACHE_TTL
        return @jwks_cache
      end

      Rails.logger.info("[CognitoJwt] Fetching JWKS from #{@jwks_uri}")
      uri  = URI(@jwks_uri)
      resp = Net::HTTP.get_response(uri)

      raise "JWKS fetch failed: #{resp.code}" unless resp.is_a?(Net::HTTPSuccess)

      @jwks_cache     = JSON.parse(resp.body)
      @jwks_cached_at = Time.now
      @jwks_cache
    end
  end

  # シングルトン
  def self.verifier
    @verifier ||= Verifier.new
  end

  def self.verify!(token)
    verifier.verify!(token)
  end
end

# =============================================================================
# config/initializers/sqs_consumer.rb
# SQS ユーザイベント消費 (Cognito EventBridge -> SQS -> Rails)
# =============================================================================
module SqsUserEvents
  class Consumer
    QUEUE_URL    = ENV['SQS_QUEUE_URL']
    MAX_MESSAGES = 10
    WAIT_SECONDS = 20   # Long Polling

    def initialize
      @sqs = Aws::SQS::Client.new(region: ENV.fetch('AWS_REGION', 'ap-northeast-1'))
    end

    # Solid Queue / Sidekiq のワーカーから呼び出すポーリングループ
    def poll
      loop do
        resp = @sqs.receive_message(
          queue_url:              QUEUE_URL,
          max_number_of_messages: MAX_MESSAGES,
          wait_time_seconds:      WAIT_SECONDS,
          attribute_names:        ['All'],
          message_attribute_names: ['All']
        )

        resp.messages.each do |msg|
          process_message(msg)
          @sqs.delete_message(
            queue_url:      QUEUE_URL,
            receipt_handle: msg.receipt_handle
          )
        end
      rescue Aws::SQS::Errors::ServiceError => e
        Rails.logger.error("[SqsConsumer] SQS error: #{e.message}")
        sleep 5
        retry
      end
    end

    private

    def process_message(msg)
      payload = JSON.parse(msg.body)
      event_type = payload['event_type']

      Rails.logger.info("[SqsConsumer] Processing event: #{event_type}")

      case event_type
      when 'USER_CONFIRMED'
        handle_user_confirmed(payload)
      when 'AdminDeleteUser'
        handle_user_deleted(payload)
      when 'AdminDisableUser'
        handle_user_disabled(payload)
      when 'AdminUpdateUserAttributes'
        handle_user_updated(payload)
      else
        Rails.logger.warn("[SqsConsumer] Unknown event_type: #{event_type}")
      end
    end

    def handle_user_confirmed(payload)
      User.find_or_create_by!(cognito_sub: payload['sub']) do |u|
        u.email  = payload['email']
        u.status = :active
      end
      Rails.logger.info("[SqsConsumer] User confirmed: #{payload['email']}")
    end

    def handle_user_deleted(payload)
      User.find_by(cognito_username: payload['username'])&.destroy!
      Rails.logger.info("[SqsConsumer] User deleted: #{payload['username']}")
    end

    def handle_user_disabled(payload)
      User.find_by(cognito_username: payload['username'])&.update!(status: :disabled)
    end

    def handle_user_updated(payload)
      User.find_by(cognito_username: payload['username'])&.sync_from_cognito!
    end
  end
end
