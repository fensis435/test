# app/controllers/auth_proxy_controller.rb
class AuthProxyController < ApplicationController
  before_action :authenticate_user_from_jwt!
  
  # Grafana用の認証エンドポイント
  def verify
    if @current_user
      # Grafanaが期待するヘッダーを返す
      response.headers['X-Auth-Request-User'] = @current_user.email
      response.headers['X-Auth-Request-Email'] = @current_user.email
      response.headers['X-Auth-Request-Groups'] = user_groups
      
      # 管理者権限の判定
      if @current_user.admin?
        response.headers['X-Auth-Request-Role'] = 'Admin'
      else
        response.headers['X-Auth-Request-Role'] = 'Viewer'
      end
      
      head :ok
    else
      head :unauthorized
    end
  end
  
  # Kubernetes Dashboard用のトークン生成エンドポイント
  def k8s_token
    if @current_user && @current_user.admin?
      token = generate_k8s_service_account_token(@current_user)
      render json: { token: token }
    else
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
  
  private
  
  def authenticate_user_from_jwt!
    token = extract_token_from_cookie || extract_token_from_header
    return unless token
    
    begin
      decoded = JWT.decode(
        token,
        Rails.application.credentials.jwt_secret,
        true,
        { algorithm: 'HS256' }
      )
      
      user_id = decoded[0]['user_id']
      @current_user = User.find_by(id: user_id)
      
      # セッションの有効性チェック
      session = Session.find_by(
        user_id: user_id,
        token: token,
        expires_at: Time.current..
      )
      
      @current_user = nil unless session
    rescue JWT::DecodeError, JWT::ExpiredSignature
      @current_user = nil
    end
  end
  
  def extract_token_from_cookie
    cookies.encrypted[:jwt_token]
  end
  
  def extract_token_from_header
    header = request.headers['Authorization']
    header&.split(' ')&.last if header&.start_with?('Bearer ')
  end
  
  def user_groups
    # ユーザーのグループやロールを取得
    @current_user.roles.pluck(:name).join(',')
  end
  
  def generate_k8s_service_account_token(user)
    # デプロイ時に作成したServiceAccountトークンを取得
    # ユーザーの権限に応じて適切なトークンを返す
    
    begin
      # Kubernetes APIクライアントの初期化
      k8s_client = Kubeclient::Client.new(
        ENV['K8S_API_URL'] || 'https://kubernetes.default.svc',
        'v1',
        ssl_options: { verify_ssl: OpenSSL::SSL::VERIFY_NONE },
        auth_options: { bearer_token_file: '/var/run/secrets/kubernetes.io/serviceaccount/token' }
      )
      
      # Secretからトークンを取得
      secret_name = case
                    when @current_user.admin?
                      'dashboard-admin-sa-token'
                    when @current_user.has_role?(:editor)
                      'dashboard-editor-sa-token'
                    else
                      'dashboard-viewer-sa-token'
                    end
      
      secret = k8s_client.get_secret(secret_name, 'kubernetes-dashboard')
      token = Base64.decode64(secret.data.token)
      
      # トークンをキャッシュ（オプション）
      Rails.cache.write("k8s_token:#{user.id}", token, expires_in: 12.hours)
      
      token
    rescue Kubeclient::ResourceNotFoundError => e
      Rails.logger.error("K8s ServiceAccount secret not found: #{e.message}")
      # フォールバック: 事前に環境変数から取得
      fetch_token_from_env(user)
    rescue => e
      Rails.logger.error("K8s token generation failed: #{e.message}")
      nil
    end
  end
  
  def fetch_token_from_env(user)
    # 環境変数またはSecretから直接取得（バックアップ方法）
    if @current_user.admin?
      ENV['K8S_ADMIN_TOKEN'] || Rails.application.credentials.dig(:kubernetes, :admin_token)
    elsif @current_user.has_role?(:editor)
      ENV['K8S_EDITOR_TOKEN'] || Rails.application.credentials.dig(:kubernetes, :editor_token)
    else
      ENV['K8S_VIEWER_TOKEN'] || Rails.application.credentials.dig(:kubernetes, :viewer_token)
    end
  end
end
