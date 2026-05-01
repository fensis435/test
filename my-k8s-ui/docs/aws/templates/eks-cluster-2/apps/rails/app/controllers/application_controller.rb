# =============================================================================
# app/controllers/concerns/cognito_authenticatable.rb
# Cognito JWT 認証 Concern
# ALBがCognitoに認証委任する場合はALBヘッダーを検証
# 内部API向けはBearerトークンを直接検証
# =============================================================================
module CognitoAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    helper_method :current_user, :current_user_groups
  end

  private

  def authenticate_user!
    @current_payload = nil
    @current_user    = nil

    # 方式1: ALB経由のCognito認証 (X-Amzn-Oidc-Dataヘッダー)
    if (alb_token = request.headers['X-Amzn-Oidc-Data'])
      @current_payload = verify_alb_jwt(alb_token)
    # 方式2: API直接アクセス (Authorization: Bearer <token>)
    elsif (bearer = extract_bearer_token)
      @current_payload = CognitoJwt.verify!(bearer)
    else
      render json: { error: 'Unauthorized' }, status: :unauthorized and return
    end

    @current_user = find_or_sync_user(@current_payload)
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::InvalidPayload => e
    Rails.logger.warn("[Auth] JWT verification failed: #{e.message}")
    render json: { error: 'Invalid token' }, status: :unauthorized
  end

  def current_user
    @current_user
  end

  def current_user_groups
    @current_payload&.dig('cognito:groups') || []
  end

  def admin_required!
    unless current_user_groups.include?('Admins')
      render json: { error: 'Forbidden' }, status: :forbidden
    end
  end

  # ---------------------------------------------------------------------------
  # ALB が付与する署名済みJWT (ECDSA P-256) を検証
  # ALBは独自の公開鍵でJWTに署名するため、AWS公開鍵エンドポイントで検証
  # ---------------------------------------------------------------------------
  def verify_alb_jwt(token)
    header = JWT.decode(token, nil, false).last
    kid    = header['kid']
    region = ENV.fetch('AWS_REGION', 'ap-northeast-1')

    # ALB公開鍵をフェッチ (VPC内からはVPC Endpoint経由)
    pub_key_uri = "https://public-keys.auth.elb.#{region}.amazonaws.com/#{kid}"
    pub_key_pem = Rails.cache.fetch("alb_pub_key_#{kid}", expires_in: 1.hour) do
      response = Faraday.get(pub_key_uri)
      raise "ALB public key fetch failed" unless response.success?
      response.body
    end

    pub_key = OpenSSL::PKey::EC.new(pub_key_pem)
    decoded = JWT.decode(token, pub_key, true, algorithms: ['ES256'])
    decoded.first
  end

  def extract_bearer_token
    header = request.headers['Authorization']
    return nil unless header&.start_with?('Bearer ')
    header.sub('Bearer ', '')
  end

  def find_or_sync_user(payload)
    sub      = payload['sub']
    email    = payload['email']
    username = payload['cognito:username'] || payload['username']

    User.find_or_initialize_by(cognito_sub: sub).tap do |u|
      u.email            = email if u.email.blank?
      u.cognito_username = username
      u.last_sign_in_at  = Time.current
      u.save! if u.changed?
    end
  end
end

# =============================================================================
# app/controllers/application_controller.rb
# =============================================================================
class ApplicationController < ActionController::API
  include CognitoAuthenticatable

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: 'Not Found' }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ヘルスチェックエンドポイント (認証スキップ)
  def health
    render json: {
      status:   'ok',
      version:  Rails.application.config.app_version,
      database: database_healthy?,
      time:     Time.current.iso8601
    }
  end

  private

  def database_healthy?
    ActiveRecord::Base.connection.execute('SELECT 1')
    true
  rescue StandardError
    false
  end
end

# =============================================================================
# app/controllers/api/v1/users_controller.rb
# ユーザ管理 API (管理者専用)
# CognitoのユーザーをAPIで作成・削除・更新し、
# ローカルDBとCognitoを同期する
# =============================================================================
module Api
  module V1
    class UsersController < ApplicationController
      before_action :admin_required!
      before_action :set_user, only: %i[show update destroy reset_password]

      # GET /api/v1/users
      def index
        users = User.order(:created_at).page(params[:page]).per(params[:per_page] || 20)
        render json: {
          users: users.as_json(only: %i[id email status created_at last_sign_in_at]),
          meta:  pagination_meta(users)
        }
      end

      # POST /api/v1/users
      def create
        user_params = params.require(:user).permit(:email, :role, :tenant_id)

        # 1. Cognito にユーザ作成
        cognito_user = create_cognito_user(user_params)

        # 2. ローカルDBに保存
        user = User.create!(
          email:             user_params[:email],
          cognito_username:  cognito_user.username,
          cognito_sub:       cognito_user.attributes.find { |a| a.name == 'sub' }&.value,
          role:              user_params[:role] || 'user',
          status:            :pending
        )

        # 3. SQSでシステム内イベント通知 (必要であれば)
        UserEventJob.perform_later('USER_CREATED', user.id)

        render json: user, status: :created
      end

      # DELETE /api/v1/users/:id
      def destroy
        # Cognito からユーザ削除
        delete_cognito_user(@user.cognito_username)

        # ローカルDBからも削除
        @user.destroy!

        head :no_content
      end

      # PUT /api/v1/users/:id
      def update
        attrs = params.require(:user).permit(:role, :status)

        # Cognito ユーザ属性を更新
        update_cognito_attributes(@user.cognito_username, attrs)

        @user.update!(attrs)
        render json: @user
      end

      # POST /api/v1/users/:id/reset_password
      def reset_password
        cognito_client.admin_reset_user_password(
          user_pool_id: ENV['COGNITO_USER_POOL_ID'],
          username:     @user.cognito_username
        )
        render json: { message: 'Password reset initiated' }
      end

      private

      def set_user
        @user = User.find(params[:id])
      end

      def cognito_client
        @cognito_client ||= Aws::CognitoIdentityProvider::Client.new(
          region: ENV.fetch('AWS_REGION', 'ap-northeast-1')
        )
      end

      def create_cognito_user(attrs)
        cognito_client.admin_create_user(
          user_pool_id:       ENV['COGNITO_USER_POOL_ID'],
          username:           attrs[:email],
          user_attributes:    [
            { name: 'email',          value: attrs[:email] },
            { name: 'email_verified', value: 'true' },
            { name: 'custom:role',    value: attrs[:role] || 'user' }
          ],
          desired_delivery_mediums: ['EMAIL']
        ).user
      end

      def delete_cognito_user(username)
        cognito_client.admin_delete_user(
          user_pool_id: ENV['COGNITO_USER_POOL_ID'],
          username:     username
        )
      end

      def update_cognito_attributes(username, attrs)
        user_attrs = []
        user_attrs << { name: 'custom:role', value: attrs[:role] } if attrs[:role]
        return if user_attrs.empty?

        cognito_client.admin_update_user_attributes(
          user_pool_id:    ENV['COGNITO_USER_POOL_ID'],
          username:        username,
          user_attributes: user_attrs
        )
      end

      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages:  collection.total_pages,
          total_count:  collection.total_count
        }
      end
    end
  end
end
