class ApplicationController < ActionController::Base
  # 標準モードなのでCSRF対策が有効
  # APIリクエストの場合のみCSRFをスキップ
  protect_from_forgery with: :null_session, if: -> {
    request.format.json? || request.path.start_with?('/api')
  }

  # セキュリティヘッダー
  before_action :set_security_headers

  private

  def set_security_headers
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
  end
end
