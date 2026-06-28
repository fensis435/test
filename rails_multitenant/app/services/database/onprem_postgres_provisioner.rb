module Services
  module Database
    class OnpremPostgresProvisioner
      include Dry::Monads[:result]

      PROVISION_POLL_INTERVAL = 3
      PROVISION_TIMEOUT = 120

      def initialize(
        k8s_client: nil,
        logger: Rails.logger
      )
        @k8s_client = k8s_client || Services::Kubernetes::Client.new
        @logger = logger
      end

      # On-prem: Deploy a PostgreSQL Pod per tenant namespace
      # Uses StatefulSet + PVC for persistence
      # @param tenant [Domain::Tenant::Tenant]
      # @param config [Domain::Tenant::DatabaseConfig]
      # @return [Dry::Monads::Result<Domain::Tenant::DatabaseConfig>]
      def provision(tenant, config)
        namespace = Rails.application.config.x.database.onprem_namespace

        deploy_postgres_statefulset(tenant, namespace)
        deploy_postgres_service(tenant, namespace)
        deploy_postgres_secret(tenant, namespace)

        wait_for_pod_ready(tenant, namespace)

        run_tenant_migrations(config)

        @logger.info("On-prem PostgreSQL provisioned for tenant: #{tenant.slug}")
        Success(config)
      rescue Timeout::Error
        Failure(Domain::Shared::Errors::TenantProvisioningError.new(
          "PostgreSQL pod did not become ready within #{PROVISION_TIMEOUT}s"
        ))
      rescue StandardError => e
        Failure(Domain::Shared::Errors::TenantProvisioningError.new(e.message))
      end

      # @param tenant [Domain::Tenant::Tenant]
      # @return [Dry::Monads::Result]
      def deprovision(tenant)
        namespace = Rails.application.config.x.database.onprem_namespace
        service_name = "postgres-#{tenant.slug}"

        @k8s_client.delete_statefulset(name: service_name, namespace: namespace)
        @k8s_client.delete_service(name: service_name, namespace: namespace)
        @k8s_client.delete_secret(name: "#{service_name}-credentials", namespace: namespace)
        @k8s_client.delete_pvc(name: "data-#{service_name}-0", namespace: namespace)

        @logger.info("On-prem PostgreSQL deprovisioned for tenant: #{tenant.slug}")
        Success(true)
      rescue StandardError => e
        Failure(Domain::Shared::Errors::TenantProvisioningError.new("Deprovision failed: #{e.message}"))
      end

      private

      def deploy_postgres_statefulset(tenant, namespace)
        service_name = "postgres-#{tenant.slug}"
        db_name = "tenant_#{tenant.slug.gsub("-", "_")}"
        password = SecureRandom.hex(32)

        manifest = {
          apiVersion: "apps/v1",
          kind: "StatefulSet",
          metadata: {
            name: service_name,
            namespace: namespace,
            labels: {
              app: "postgres",
              "multitenant.io/tenant-slug": tenant.slug,
              "multitenant.io/tenant-id": tenant.id
            }
          },
          spec: {
            serviceName: service_name,
            replicas: 1,
            selector: {
              matchLabels: { app: service_name }
            },
            template: {
              metadata: {
                labels: { app: service_name }
              },
              spec: {
                containers: [{
                  name: "postgres",
                  image: "postgres:16-alpine",
                  ports: [{ containerPort: 5432 }],
                  env: [
                    { name: "POSTGRES_DB", value: db_name },
                    { name: "POSTGRES_USER", value: "tenant_user" },
                    {
                      name: "POSTGRES_PASSWORD",
                      valueFrom: {
                        secretKeyRef: {
                          name: "#{service_name}-credentials",
                          key: "password"
                        }
                      }
                    },
                    { name: "PGDATA", value: "/var/lib/postgresql/data/pgdata" }
                  ],
                  resources: {
                    requests: { memory: "256Mi", cpu: "100m" },
                    limits: { memory: "1Gi", cpu: "500m" }
                  },
                  volumeMounts: [{
                    name: "data",
                    mountPath: "/var/lib/postgresql/data"
                  }],
                  readinessProbe: {
                    exec: {
                      command: ["pg_isready", "-U", "tenant_user", "-d", db_name]
                    },
                    initialDelaySeconds: 5,
                    periodSeconds: 5,
                    failureThreshold: 6
                  },
                  livenessProbe: {
                    exec: {
                      command: ["pg_isready", "-U", "tenant_user", "-d", db_name]
                    },
                    initialDelaySeconds: 30,
                    periodSeconds: 10
                  }
                }],
                securityContext: {
                  runAsNonRoot: true,
                  runAsUser: 999,
                  fsGroup: 999
                }
              }
            },
            volumeClaimTemplates: [{
              metadata: { name: "data" },
              spec: {
                accessModes: ["ReadWriteOnce"],
                resources: {
                  requests: { storage: "10Gi" }
                }
              }
            }]
          }
        }

        @k8s_client.create_secret(
          name: "#{service_name}-credentials",
          namespace: namespace,
          data: { "password" => Base64.strict_encode64(password) }
        )

        @k8s_client.apply_statefulset(manifest)
      end

      def deploy_postgres_service(tenant, namespace)
        service_name = "postgres-#{tenant.slug}"

        manifest = {
          apiVersion: "v1",
          kind: "Service",
          metadata: {
            name: service_name,
            namespace: namespace,
            labels: {
              "multitenant.io/tenant-slug": tenant.slug
            }
          },
          spec: {
            selector: { app: service_name },
            ports: [{ port: 5432, targetPort: 5432, protocol: "TCP" }],
            type: "ClusterIP"
          }
        }

        @k8s_client.apply_service(manifest)
      end

      def deploy_postgres_secret(tenant, namespace)
        # Already created in deploy_postgres_statefulset, nothing extra needed
      end

      def wait_for_pod_ready(tenant, namespace)
        service_name = "postgres-#{tenant.slug}"
        deadline = Time.current + PROVISION_TIMEOUT

        loop do
          raise Timeout::Error if Time.current > deadline

          ready = @k8s_client.statefulset_ready?(name: service_name, namespace: namespace)
          break if ready

          @logger.debug("Waiting for pod #{service_name} to be ready...")
          sleep(PROVISION_POLL_INTERVAL)
        end
      end

      def run_tenant_migrations(config)
        # Connect to the new database and run migrations
        pool = DatabaseSwitcher::ConnectionPoolRegistry.instance.fetch_or_create(config)
        pool.with_connection do |conn|
          ActiveRecord::MigrationContext.new(
            Rails.root.join("db/tenant_migrations").to_s,
            ActiveRecord::SchemaMigration
          ).migrate
        end
      end
    end
  end
end
