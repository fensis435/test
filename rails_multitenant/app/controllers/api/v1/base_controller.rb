module Api
  module V1
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      before_action :authenticate!
      before_action :require_active_tenant!

      rescue_from Domain::Shared::Errors::NotFoundError, with: :render_not_found
      rescue_from Domain::Shared::Errors::ValidationError, with: :render_unprocessable
      rescue_from Domain::Shared::Errors::UnauthorizedError, with: :render_unauthorized
      rescue_from Domain::Shared::Errors::ForbiddenError, with: :render_forbidden
      rescue_from Domain::Shared::Errors::TenantSuspendedError, with: :render_tenant_suspended
      rescue_from Domain::Shared::Errors::InvalidStateTransitionError, with: :render_unprocessable
      rescue_from Domain::Shared::Errors::ConflictError, with: :render_conflict
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      attr_reader :current_user, :current_tenant

      private

      def authenticate!
        token = extract_token
        raise Domain::Shared::Errors::UnauthorizedError unless token.present?

        result = jwt_verifier.verify(token)

        case result
        in Dry::Monads::Success(payload)
          @current_user = build_current_user(payload)
        in Dry::Monads::Failure(error)
          raise Domain::Shared::Errors::UnauthorizedError, error.message
        end
      end

      def require_active_tenant!
        @current_tenant = TenantResolver::TenantContext.current_tenant

        if @current_tenant.nil?
          raise Domain::Shared::Errors::TenantNotFoundError.new("No tenant context")
        end

        if @current_tenant.suspended?
          raise Domain::Shared::Errors::TenantSuspendedError.new(@current_tenant.slug)
        end
      end

      def require_admin!
        raise Domain::Shared::Errors::ForbiddenError unless current_user&.admin?
      end

      def require_owner!
        raise Domain::Shared::Errors::ForbiddenError unless current_user&.owner?
      end

      def jwt_verifier
        @jwt_verifier ||= Services::Auth::CognitoJwtVerifier.new
      end

      def extract_token
        auth_header = request.headers["Authorization"]
        return nil if auth_header.blank?

        auth_header.sub(/\ABearer\s+/i, "").presence
      end

      def build_current_user(payload)
        CurrentUser.new(
          sub: payload["sub"],
          email: payload["email"],
          tenant_slug: payload["custom:tenant_slug"] || payload["tenant_slug"],
          role: payload["custom:role"] || "member",
          cognito_groups: payload["cognito:groups"] || []
        )
      end

      def paginate(collection, serializer_class: nil)
        pagy_instance, records = pagy(collection, items: per_page)

        {
          data: records,
          meta: {
            current_page: pagy_instance.page,
            per_page: pagy_instance.vars[:items],
            total_count: pagy_instance.count,
            total_pages: pagy_instance.pages
          }
        }
      end

      def per_page
        [params[:per_page].to_i.clamp(1, 100), 25].max
      end

      def render_success(data, status: :ok, meta: nil)
        body = { data: data }
        body[:meta] = meta if meta.present?
        render json: body, status: status
      end

      def render_created(data)
        render_success(data, status: :created)
      end

      def render_not_found(error)
        render json: error_body("NOT_FOUND", error.message), status: :not_found
      end

      def render_unauthorized(error = nil)
        message = error&.message || "Unauthorized"
        render json: error_body("UNAUTHORIZED", message), status: :unauthorized
      end

      def render_forbidden(error = nil)
        message = error&.message || "Forbidden"
        render json: error_body("FORBIDDEN", message), status: :forbidden
      end

      def render_unprocessable(error)
        body = error_body("VALIDATION_ERROR", error.message)
        body[:details] = error.details if error.respond_to?(:details) && error.details.present?
        render json: body, status: :unprocessable_entity
      end

      def render_tenant_suspended(error)
        render json: error_body("TENANT_SUSPENDED", error.message), status: :forbidden
      end

      def render_conflict(error)
        render json: error_body("CONFLICT", error.message), status: :conflict
      end

      def render_bad_request(error)
        render json: error_body("BAD_REQUEST", error.message), status: :bad_request
      end

      def render_internal_error(error)
        Rails.logger.error("Internal error: #{error.class} - #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}")
        render json: error_body("INTERNAL_ERROR", "Internal server error"), status: :internal_server_error
      end

      def error_body(code, message)
        {
          error: {
            code: code,
            message: message,
            request_id: request.request_id,
            timestamp: Time.current.iso8601
          }
        }
      end
    end
  end
end
