module Api
  module V1
    module Admin
      class TenantsController < BaseController
        skip_before_action :require_active_tenant!
        before_action :require_system_admin!
        before_action :set_tenant, only: %i[show update destroy suspend activate provision_database]

        def index
          tenants = tenant_repository.find_all(
            page: params[:page]&.to_i || 1,
            per_page: params[:per_page]&.to_i || 25,
            filters: filter_params
          )
          total = tenant_repository.count(filters: filter_params)

          render_success(
            tenants.map { |t| serialize_tenant(t) },
            meta: {
              total_count: total,
              page: params[:page]&.to_i || 1,
              per_page: params[:per_page]&.to_i || 25
            }
          )
        end

        def show
          render_success(serialize_tenant(@tenant))
        end

        def create
          result = tenant_provisioner.provision(
            slug: tenant_create_params[:slug],
            name: tenant_create_params[:name],
            plan: tenant_create_params[:plan],
            settings: tenant_create_params[:settings]&.to_unsafe_h || {}
          )

          case result
          in Dry::Monads::Success(tenant)
            render_created(serialize_tenant(tenant))
          in Dry::Monads::Failure(error)
            render_provisioning_error(error)
          end
        end

        def update
          updated = Domain::Tenant::Tenant.new(
            id: @tenant.id,
            slug: @tenant.slug,
            name: tenant_update_params[:name] || @tenant.name,
            status: @tenant.status,
            plan: tenant_update_params[:plan] || @tenant.plan,
            settings: @tenant.settings.merge(tenant_update_params[:settings]&.to_unsafe_h || {}),
            database_config: @tenant.database_config,
            created_at: @tenant.created_at,
            updated_at: Time.current,
            suspended_at: @tenant.suspended_at
          )
          saved = tenant_repository.save(updated)
          render_success(serialize_tenant(saved))
        rescue Domain::Shared::Errors::ValidationError => e
          render_unprocessable(e)
        end

        def destroy
          result = tenant_provisioner.terminate(@tenant)

          case result
          in Dry::Monads::Success
            head :no_content
          in Dry::Monads::Failure(error)
            render_unprocessable(error)
          end
        end

        def suspend
          reason = params[:reason]
          result = tenant_provisioner.suspend(@tenant, reason: reason)

          case result
          in Dry::Monads::Success(tenant)
            render_success(serialize_tenant(tenant))
          in Dry::Monads::Failure(error)
            render_unprocessable(error)
          end
        end

        def activate
          result = tenant_provisioner.activate(@tenant)

          case result
          in Dry::Monads::Success(tenant)
            render_success(serialize_tenant(tenant))
          in Dry::Monads::Failure(error)
            render_unprocessable(error)
          end
        end

        def provision_database
          if @tenant.database_provisioned?
            return render json: error_body("CONFLICT", "Database already provisioned"), status: :conflict
          end

          ProvisionTenantDatabaseJob.perform_later(@tenant.id)
          render_success({ message: "Database provisioning started", tenant_id: @tenant.id })
        end

        private

        def require_system_admin!
          raise Domain::Shared::Errors::ForbiddenError unless current_user&.system_admin?
        end

        def set_tenant
          @tenant = tenant_repository.find_by_id(params[:id]) ||
                    tenant_repository.find_by_slug(params[:id])
          raise Domain::Shared::Errors::NotFoundError.new("Tenant", params[:id]) unless @tenant
        end

        def tenant_repository
          @tenant_repository ||= Repositories::TenantRepository.new
        end

        def tenant_provisioner
          @tenant_provisioner ||= Services::Tenant::TenantProvisioner.new(
            tenant_repository: tenant_repository
          )
        end

        def tenant_create_params
          params.require(:tenant).permit(:slug, :name, :plan, settings: {})
        end

        def tenant_update_params
          params.require(:tenant).permit(:name, :plan, settings: {})
        end

        def filter_params
          params.permit(:status, :plan, :name, :created_after).to_h.symbolize_keys
        end

        def serialize_tenant(tenant)
          Serializers::TenantSerializer.new(tenant).as_json
        end

        def render_provisioning_error(error)
          case error
          when Domain::Shared::Errors::ConflictError
            render_conflict(error)
          when Domain::Shared::Errors::ValidationError
            render_unprocessable(error)
          else
            render json: error_body("PROVISIONING_ERROR", error.message), status: :unprocessable_entity
          end
        end
      end
    end
  end
end
