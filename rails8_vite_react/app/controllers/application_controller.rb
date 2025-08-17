class ApplicationController < ActionController::Base
  #before_action :update_user_login_time
  #after_action :schedule_app_lifecycle

  # 標準モードなのでCSRF対策が有効
  # APIリクエストの場合のみCSRFをスキップ
  protect_from_forgery with: :null_session, if: -> {
    request.format.json? || request.path.start_with?('/api')
  }

  # セキュリティヘッダー
  before_action :set_security_headers

  def ready_check
    # Kubernetes readiness probe用
    begin
      # Database接続チェック
      ActiveRecord::Base.connection.execute('SELECT 1')
      
      # Redis接続チェック（Sidekiq使用時）
      Sidekiq.redis { |conn| conn.ping } if defined?(Sidekiq)
      
      render json: { status: 'ready' }, status: 200
    rescue => e
      render json: { status: 'not ready', error: e.message }, status: 503
    end
  end

  private

  def set_security_headers
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
  end

  def update_user_login_time
    current_user.update_column(:last_login_at, Time.current)
  end

  def schedule_app_lifecycle
    return unless user_signed_in?
    
    # ログイン時にアプリ起動をスケジュール
    if session[:just_signed_in]
      current_user.start_app_on_login
      session.delete(:just_signed_in)
    end
  end

end
