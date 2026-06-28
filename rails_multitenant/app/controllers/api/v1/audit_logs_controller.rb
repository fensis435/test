module Api
  module V1
    class AuditLogsController < BaseController
      before_action :require_admin!

      def index
        scope = AuditLog.all
        scope = scope.by_action(params[:action_filter]) if params[:action_filter].present?
        scope = scope.by_actor(params[:actor_sub]) if params[:actor_sub].present?
        scope = scope.by_resource(params[:resource_type], params[:resource_id]) if params[:resource_type].present? && params[:resource_id].present?
        scope = scope.recent

        result = paginate(scope)
        render_success(
          result[:data].map { |log| serialize_log(log) },
          meta: result[:meta]
        )
      end

      def show
        log = AuditLog.find_by(id: params[:id])
        raise Domain::Shared::Errors::NotFoundError.new("AuditLog", params[:id]) unless log

        render_success(serialize_log(log))
      end

      private

      def serialize_log(log)
        {
          id: log.id,
          tenant_id: log.tenant_id,
          actor_sub: log.actor_sub,
          actor_email: log.actor_email,
          actor_role: log.actor_role,
          action: log.action,
          resource_type: log.resource_type,
          resource_id: log.resource_id,
          metadata: log.metadata,
          occurred_at: log.occurred_at&.iso8601,
          created_at: log.created_at&.iso8601
        }
      end
    end
  end
end
