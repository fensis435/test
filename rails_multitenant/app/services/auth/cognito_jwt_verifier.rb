module Services
  module Auth
    class CognitoJwtVerifier
      include Dry::Monads[:result]

      ALGORITHM = "RS256"
      JWKS_CACHE_TTL = 3600
      CLOCK_SKEW_TOLERANCE = 30

      def initialize(
        user_pool_id: nil,
        region: nil,
        jwks_cache: nil,
        logger: Rails.logger
      )
        @user_pool_id = user_pool_id || Rails.application.config.x.auth.cognito_user_pool_id
        @region = region || Rails.application.config.x.auth.cognito_region
        @jwks_cache = jwks_cache || JwksCache.new
        @logger = logger
      end

      # @param token [String] JWT Bearer token
      # @return [Dry::Monads::Result]
      def verify(token)
        return Failure(Domain::Shared::Errors::TokenVerificationError.new("Token is blank")) if token.blank?

        header = decode_header(token)
        return Failure(Domain::Shared::Errors::TokenVerificationError.new("Cannot decode token header")) unless header

        key = find_jwk(header["kid"])
        return Failure(Domain::Shared::Errors::TokenVerificationError.new("No matching JWK for kid: #{header["kid"]}")) unless key

        payload = decode_token(token, key)
        return Failure(payload) if payload.is_a?(StandardError)

        validate_claims(payload)
      rescue StandardError => e
        @logger.error("JWT verification error: #{e.class} - #{e.message}")
        Failure(Domain::Shared::Errors::TokenVerificationError.new(e.message))
      end

      private

      def issuer
        "https://cognito-idp.#{@region}.amazonaws.com/#{@user_pool_id}"
      end

      def jwks_uri
        "#{issuer}/.well-known/jwks.json"
      end

      def decode_header(token)
        header_segment = token.split(".").first
        return nil if header_segment.blank?

        decoded = Base64.urlsafe_decode64(header_segment + "==")
        JSON.parse(decoded)
      rescue StandardError
        nil
      end

      def find_jwk(kid)
        jwks = @jwks_cache.fetch(jwks_uri)
        return nil unless jwks

        matching = jwks["keys"]&.find { |k| k["kid"] == kid }
        return nil unless matching

        build_public_key(matching)
      rescue StandardError => e
        @logger.error("JWK fetch error: #{e.message}")
        nil
      end

      def build_public_key(jwk)
        JWT::JWK.import(jwk.transform_keys(&:to_sym)).public_key
      rescue StandardError => e
        @logger.error("JWK key build error: #{e.message}")
        nil
      end

      def decode_token(token, key)
        payload, = JWT.decode(
          token,
          key,
          true,
          {
            algorithms: [ALGORITHM],
            iss: issuer,
            verify_iss: true,
            verify_iat: true,
            leeway: CLOCK_SKEW_TOLERANCE
          }
        )
        payload
      rescue JWT::ExpiredSignature
        Domain::Shared::Errors::TokenExpiredError.new
      rescue JWT::InvalidIssuerError
        Domain::Shared::Errors::TokenVerificationError.new("Invalid issuer")
      rescue JWT::DecodeError => e
        Domain::Shared::Errors::TokenVerificationError.new(e.message)
      end

      def validate_claims(payload)
        errors = []

        errors << "Missing sub claim" if payload["sub"].blank?
        errors << "Missing email claim" if payload["email"].blank?
        errors << "Token not for access" if payload["token_use"] && !%w[access id].include?(payload["token_use"])

        if errors.any?
          return Failure(Domain::Shared::Errors::TokenVerificationError.new(errors.join(", ")))
        end

        Success(payload)
      end
    end
  end
end
