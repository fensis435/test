# frozen_string_literal: true

module Api
  module V1
    # ----------------------------------------------------------------------------
    # このテストアプリで唯一意味のあるエンドポイント。
    # Authorizationヘッダで受け取ったAccess TokenをTokenVerifierで検証し、
    # 成功すればクレームをそのまま返す。Reactのトップページはこの結果を
    # 表示するだけで、「ブラウザで発行されたトークンがRailsバックエンドで
    # 実際に検証できる」ことの証明になる。
    # ----------------------------------------------------------------------------
    class WhoamiController < ApplicationController
      def show
        claims = TokenVerifier.new.verify!(bearer_token)

        render json: {
          verified: true,
          issuer: claims["iss"],
          subject: claims["sub"],
          claims: claims
        }
      rescue TokenVerifier::TokenExpiredError => e
        render json: { verified: false, error: "token_expired", message: e.message }, status: :unauthorized
      rescue TokenVerifier::InvalidTokenError => e
        render json: { verified: false, error: "invalid_token", message: e.message }, status: :unauthorized
      rescue TokenVerifier::Error => e
        render json: { verified: false, error: "verification_failed", message: e.message },
               status: :service_unavailable
      end

      private

      def bearer_token
        header = request.headers["Authorization"]
        return nil unless header&.start_with?("Bearer ")

        header.split(" ", 2).last
      end
    end
  end
end
