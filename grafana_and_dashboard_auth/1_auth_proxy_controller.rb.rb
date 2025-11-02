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
    # Kubernetes APIを使ってServiceAccountのトークンを取得
    # または事前に作成したトークンをユーザーに紐付けて返す
    k8s_client = Kubeclient::Client.new(
      ENV['K8S_API_URL'],
      'v1',
      ssl_options: { verify_ssl: OpenSSL::SSL::VERIFY_NONE },
      auth_options: { bearer_token_file: '/var/run/secrets/kubernetes.io/serviceaccount/token' }
    )
    
    # ユーザー専用のServiceAccountからトークンを取得
    service_account = k8s_client.get_service_account(
      "sa-#{user.id}",
      'default'
    )
    
    secret_name = service_account.secrets.first.name
    secret = k8s_client.get_secret(secret_name, 'default')
    Base64.decode64(secret.data.token)
  rescue => e
    Rails.logger.error("K8s token generation failed: #{e.message}")
    nil
  end
end
