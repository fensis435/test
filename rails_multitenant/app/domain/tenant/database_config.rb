module Domain
  module Tenant
    class DatabaseConfig
      attr_reader :host, :port, :database, :username, :schema,
                  :platform, :endpoint_type, :ssl_mode, :pool_size

      def initialize(
        host:,
        port:,
        database:,
        username:,
        schema:,
        platform:,
        endpoint_type: "rds",
        ssl_mode: "require",
        pool_size: 5
      )
        @host = host
        @port = port.to_i
        @database = database
        @username = username
        @schema = schema
        @platform = platform
        @endpoint_type = endpoint_type
        @ssl_mode = ssl_mode
        @pool_size = pool_size.to_i
      end

      def self.for_aws(tenant_slug:, rds_host:, rds_port: 5432)
        new(
          host: rds_host,
          port: rds_port,
          database: "tenant_#{tenant_slug.gsub("-", "_")}",
          username: "tenant_#{tenant_slug.gsub("-", "_")}_user",
          schema: "public",
          platform: "aws",
          endpoint_type: "rds",
          ssl_mode: "require"
        )
      end

      def self.for_onprem(tenant_slug:, namespace:)
        service_name = "postgres-#{tenant_slug}"
        new(
          host: "#{service_name}.#{namespace}.svc.cluster.local",
          port: 5432,
          database: "tenant_#{tenant_slug.gsub("-", "_")}",
          username: "tenant_user",
          schema: "public",
          platform: "onprem",
          endpoint_type: "pod",
          ssl_mode: "disable"
        )
      end

      def aws?
        platform == "aws"
      end

      def onprem?
        platform == "onprem"
      end

      def connection_string(password: nil)
        base = "postgresql://#{username}#{password ? ":#{password}" : ""}@#{host}:#{port}/#{database}"
        ssl_mode == "require" ? "#{base}?sslmode=require" : base
      end

      def to_h
        {
          host: host,
          port: port,
          database: database,
          username: username,
          schema: schema,
          platform: platform,
          endpoint_type: endpoint_type,
          ssl_mode: ssl_mode,
          pool_size: pool_size
        }
      end

      def ==(other)
        other.is_a?(self.class) && to_h == other.to_h
      end
    end
  end
end
