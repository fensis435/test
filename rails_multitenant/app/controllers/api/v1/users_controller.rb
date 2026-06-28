module Api
  module V1
    class UsersController < BaseController
      before_action :set_user, only: %i[show update destroy]
      before_action :require_admin!, only: %i[create update destroy]

      def index
        scope = user_scope
        scope = scope.search(params[:q]) if params[:q].present?
        scope = scope.by_role(params[:role]) if params[:role].present?

        result = paginate(scope)
        render_success(
          result[:data].map { |u| serialize_user(u) },
          meta: result[:meta]
        )
      end

      def me
        user = UserRecord.find_by(cognito_sub: current_user.sub)
        raise Domain::Shared::Errors::NotFoundError.new("User", current_user.sub) unless user

        render_success(serialize_user(user))
      end

      def show
        render_success(serialize_user(@user))
      end

      def create
        user = UserRecord.new(user_create_params)

        if user.save
          AuditLog.record(
            tenant: current_tenant,
            actor: current_user,
            action: "user.created",
            resource_type: "User",
            resource_id: user.id,
            metadata: { email: user.email, role: user.role }
          )
          render_created(serialize_user(user))
        else
          raise Domain::Shared::Errors::ValidationError.new(
            "User creation failed",
            details: user.errors.full_messages
          )
        end
      end

      def update
        if @user.update(user_update_params)
          AuditLog.record(
            tenant: current_tenant,
            actor: current_user,
            action: "user.updated",
            resource_type: "User",
            resource_id: @user.id,
            metadata: user_update_params.to_h
          )
          render_success(serialize_user(@user))
        else
          raise Domain::Shared::Errors::ValidationError.new(
            "User update failed",
            details: @user.errors.full_messages
          )
        end
      end

      def destroy
        @user.deactivate!
        AuditLog.record(
          tenant: current_tenant,
          actor: current_user,
          action: "user.deactivated",
          resource_type: "User",
          resource_id: @user.id,
          metadata: {}
        )
        head :no_content
      end

      private

      def set_user
        @user = user_scope.find_by!(id: params[:id])
      rescue ActiveRecord::RecordNotFound
        raise Domain::Shared::Errors::NotFoundError.new("User", params[:id])
      end

      def user_scope
        UserRecord.active
      end

      def user_create_params
        params.require(:user).permit(:cognito_sub, :email, :display_name, :role)
      end

      def user_update_params
        allowed = [:display_name]
        allowed << :role if current_user.owner?
        params.require(:user).permit(*allowed)
      end

      def serialize_user(user)
        Serializers::UserSerializer.new(user).as_json
      end
    end
  end
end
