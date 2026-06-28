module Services
  module Aws
    class SecretsManagerClient
      SECRET_PREFIX = "multitenant/tenant-credentials"

      def initialize(region: nil, logger: Rails.logger)
        @region = region || ENV.fetch("AWS_REGION", "ap-northeast-1")
        @logger = logger
        @client = build_client
      end

      # @param username [String]
      # @param password [String]
      # @return [Boolean]
      def store_tenant_credential(username:, password:)
        secret_name = "#{SECRET_PREFIX}/#{username}"
        secret_value = { username: username, password: password }.to_json

        begin
          @client.create_secret(
            name: secret_name,
            secret_string: secret_value,
            description: "Tenant DB credentials for #{username}"
          )
        rescue ::Aws::SecretsManager::Errors::ResourceExistsException
          @client.put_secret_value(
            secret_id: secret_name,
            secret_string: secret_value
          )
        end

        @logger.info("Stored credentials for #{username} in SecretsManager")
        true
      rescue ::Aws::SecretsManager::Errors::ServiceError => e
        @logger.error("SecretsManager error: #{e.message}")
        false
      end

      # @param username [String]
      # @return [String, nil] password
      def fetch_tenant_credential(username:)
        secret_name = "#{SECRET_PREFIX}/#{username}"
        response = @client.get_secret_value(secret_id: secret_name)
        parsed = JSON.parse(response.secret_string)
        parsed["password"]
      rescue ::Aws::SecretsManager::Errors::ResourceNotFoundException
        @logger.warn("Credential not found for #{username}")
        nil
      rescue ::Aws::SecretsManager::Errors::ServiceError => e
        @logger.error("SecretsManager fetch error: #{e.message}")
        nil
      end

      # @param username [String]
      # @return [Boolean]
      def delete_tenant_credential(username:)
        secret_name = "#{SECRET_PREFIX}/#{username}"
        @client.delete_secret(
          secret_id: secret_name,
          force_delete_without_recovery: false,
          recovery_window_in_days: 7
        )
        true
      rescue ::Aws::SecretsManager::Errors::ResourceNotFoundException
        true
      rescue ::Aws::SecretsManager::Errors::ServiceError => e
        @logger.error("SecretsManager delete error: #{e.message}")
        false
      end

      private

      def build_client
        require "aws-sdk-secretsmanager"

        options = { region: @region }

        if ENV["AWS_ENDPOINT_URL"].present?
          options[:endpoint] = ENV["AWS_ENDPOINT_URL"]
        end

        ::Aws::SecretsManager::Client.new(options)
      end
    end
  end
end
