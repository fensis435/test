module Services
  module Kubernetes
    class Client
      API_TIMEOUT = 30

      def initialize(
        kubeconfig_path: nil,
        in_cluster: nil,
        logger: Rails.logger
      )
        @logger = logger
        @in_cluster = in_cluster.nil? ? detect_in_cluster? : in_cluster
        @kubeconfig_path = kubeconfig_path || ENV["KUBECONFIG"] || File.expand_path("~/.kube/config")
        @http_client = build_http_client
      end

      # @param manifest [Hash]
      def apply_statefulset(manifest)
        namespace = manifest.dig(:metadata, :namespace)
        name = manifest.dig(:metadata, :name)

        begin
          patch_resource(
            path: "/apis/apps/v1/namespaces/#{namespace}/statefulsets/#{name}",
            body: manifest
          )
        rescue NotFoundError
          create_resource(
            path: "/apis/apps/v1/namespaces/#{namespace}/statefulsets",
            body: manifest
          )
        end
      end

      # @param manifest [Hash]
      def apply_service(manifest)
        namespace = manifest.dig(:metadata, :namespace)
        name = manifest.dig(:metadata, :name)

        begin
          patch_resource(
            path: "/api/v1/namespaces/#{namespace}/services/#{name}",
            body: manifest
          )
        rescue NotFoundError
          create_resource(
            path: "/api/v1/namespaces/#{namespace}/services",
            body: manifest
          )
        end
      end

      # @param name [String]
      # @param namespace [String]
      # @param data [Hash] base64-encoded values
      def create_secret(name:, namespace:, data:)
        manifest = {
          apiVersion: "v1",
          kind: "Secret",
          metadata: { name: name, namespace: namespace },
          type: "Opaque",
          data: data
        }

        begin
          patch_resource(
            path: "/api/v1/namespaces/#{namespace}/secrets/#{name}",
            body: manifest
          )
        rescue NotFoundError
          create_resource(
            path: "/api/v1/namespaces/#{namespace}/secrets",
            body: manifest
          )
        end
      end

      # @param name [String]
      # @param namespace [String]
      # @return [Boolean]
      def statefulset_ready?(name:, namespace:)
        response = get_resource(
          path: "/apis/apps/v1/namespaces/#{namespace}/statefulsets/#{name}"
        )

        spec_replicas = response.dig("spec", "replicas").to_i
        ready_replicas = response.dig("status", "readyReplicas").to_i

        spec_replicas > 0 && ready_replicas >= spec_replicas
      rescue StandardError
        false
      end

      def delete_statefulset(name:, namespace:)
        delete_resource(path: "/apis/apps/v1/namespaces/#{namespace}/statefulsets/#{name}")
      end

      def delete_service(name:, namespace:)
        delete_resource(path: "/api/v1/namespaces/#{namespace}/services/#{name}")
      end

      def delete_secret(name:, namespace:)
        delete_resource(path: "/api/v1/namespaces/#{namespace}/secrets/#{name}")
      end

      def delete_pvc(name:, namespace:)
        delete_resource(path: "/api/v1/namespaces/#{namespace}/persistentvolumeclaims/#{name}")
      end

      private

      def get_resource(path:)
        response = @http_client.get(api_url(path))
        handle_response(response)
      end

      def create_resource(path:, body:)
        response = @http_client.post(api_url(path), body.to_json, default_headers)
        handle_response(response)
      end

      def patch_resource(path:, body:)
        response = @http_client.patch(api_url(path), body.to_json, default_headers.merge("Content-Type" => "application/merge-patch+json"))
        handle_response(response)
      end

      def delete_resource(path:)
        response = @http_client.delete(api_url(path))
        handle_response(response)
      rescue NotFoundError
        nil # Already deleted
      end

      def handle_response(response)
        case response.code.to_i
        when 200..299
          JSON.parse(response.body) if response.body.present?
        when 404
          raise NotFoundError, "Resource not found"
        when 409
          raise ConflictError, "Resource already exists"
        else
          raise Error, "Kubernetes API error #{response.code}: #{response.body}"
        end
      end

      def api_url(path)
        "#{base_url}#{path}"
      end

      def base_url
        if @in_cluster
          "https://kubernetes.default.svc"
        else
          extract_server_from_kubeconfig
        end
      end

      def build_http_client
        require "net/http"

        client = Object.new
        ca_cert = in_cluster_ca_cert if @in_cluster

        client.define_singleton_method(:get) do |url|
          uri = URI.parse(url)
          perform_request(uri, Net::HTTP::Get.new(uri.request_uri), ca_cert)
        end

        client
      end

      def default_headers
        {
          "Content-Type" => "application/json",
          "Authorization" => "Bearer #{service_account_token}"
        }
      end

      def service_account_token
        if @in_cluster
          File.read("/var/run/secrets/kubernetes.io/serviceaccount/token")
        else
          extract_token_from_kubeconfig
        end
      end

      def in_cluster_ca_cert
        "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
      end

      def detect_in_cluster?
        File.exist?("/var/run/secrets/kubernetes.io/serviceaccount/token")
      end

      def extract_server_from_kubeconfig
        config = YAML.load_file(@kubeconfig_path)
        config.dig("clusters", 0, "cluster", "server")
      rescue StandardError
        "http://localhost:8001"
      end

      def extract_token_from_kubeconfig
        config = YAML.load_file(@kubeconfig_path)
        config.dig("users", 0, "user", "token") || ""
      rescue StandardError
        ""
      end

      Error = Class.new(StandardError)
      NotFoundError = Class.new(Error)
      ConflictError = Class.new(Error)
    end
  end
end
