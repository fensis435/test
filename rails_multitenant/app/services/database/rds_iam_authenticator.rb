module Services
  module Database
    class RdsIamAuthenticator
      TOKEN_TTL = 900

      def initialize(region: nil)
        @region = region || ENV.fetch("AWS_REGION", "ap-northeast-1")
        @cache = {}
        @mutex = Mutex.new
      end

      # Generate RDS IAM auth token
      # @param host [String]
      # @param port [Integer]
      # @param username [String]
      # @param region [String]
      # @return [String] auth token
      def generate_token(host:, port:, username:, region: nil)
        effective_region = region || @region
        cache_key = "#{host}:#{port}:#{username}"

        @mutex.synchronize do
          entry = @cache[cache_key]
          if entry && Time.current < entry[:expires_at]
            return entry[:token]
          end

          token = request_token(
            host: host,
            port: port,
            username: username,
            region: effective_region
          )

          @cache[cache_key] = {
            token: token,
            expires_at: Time.current + TOKEN_TTL - 60
          }

          token
        end
      end

      private

      def request_token(host:, port:, username:, region:)
        require "aws-sdk-rds"

        signer = Aws::RDS::AuthTokenGenerator.new(region: region)
        signer.auth_token(
          endpoint: "#{host}:#{port}",
          region: region,
          user_name: username
        )
      end
    end
  end
end
