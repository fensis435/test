module Services
  module Auth
    class JwksCache
      TTL = 3600
      MUTEX = Mutex.new

      def initialize(http_client: nil)
        @cache = {}
        @http_client = http_client
      end

      # @param uri [String] JWKS URI
      # @return [Hash, nil]
      def fetch(uri)
        MUTEX.synchronize do
          entry = @cache[uri]

          if entry && !expired?(entry)
            return entry[:data]
          end

          data = fetch_from_remote(uri)
          @cache[uri] = { data: data, fetched_at: Time.current } if data
          data
        end
      end

      def invalidate(uri = nil)
        MUTEX.synchronize do
          if uri
            @cache.delete(uri)
          else
            @cache.clear
          end
        end
      end

      private

      def expired?(entry)
        Time.current > entry[:fetched_at] + TTL
      end

      def fetch_from_remote(uri)
        response = http_get(uri)
        JSON.parse(response.body)
      rescue StandardError => e
        Rails.logger.error("JWKS fetch failed for #{uri}: #{e.message}")
        nil
      end

      def http_get(uri)
        if @http_client
          @http_client.get(uri)
        else
          require "net/http"
          parsed = URI.parse(uri)
          http = Net::HTTP.new(parsed.host, parsed.port)
          http.use_ssl = parsed.scheme == "https"
          http.read_timeout = 5
          http.open_timeout = 5
          http.get(parsed.request_uri)
        end
      end
    end
  end
end
