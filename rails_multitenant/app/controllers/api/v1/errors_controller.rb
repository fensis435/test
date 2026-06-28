module Api
  module V1
    class ErrorsController < ActionController::API
      def not_found
        render json: {
          error: {
            code: "NOT_FOUND",
            message: "The requested resource was not found",
            request_id: request.request_id,
            timestamp: Time.current.iso8601
          }
        }, status: :not_found
      end

      def unprocessable
        render json: {
          error: {
            code: "UNPROCESSABLE_ENTITY",
            message: "The request could not be processed",
            request_id: request.request_id,
            timestamp: Time.current.iso8601
          }
        }, status: :unprocessable_entity
      end

      def internal_server_error
        render json: {
          error: {
            code: "INTERNAL_SERVER_ERROR",
            message: "An internal server error occurred",
            request_id: request.request_id,
            timestamp: Time.current.iso8601
          }
        }, status: :internal_server_error
      end
    end
  end
end
