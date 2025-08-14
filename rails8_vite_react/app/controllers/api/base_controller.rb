class Api::BaseController < ApplicationController
  # APIなので認証トークンベース、CSRFは無効
  protect_from_forgery with: :null_session
  
  # CORS設定（必要に応じて）
  before_action :set_cors_headers
  
  # 共通のエラーハンドリング
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :record_invalid
  rescue_from JWT::ExpiredSignature, with: :token_expired
  rescue_from JWT::DecodeError, with: :token_invalid
  
  private
  
  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = ENV.fetch('FRONTEND_URL', 'http://localhost:5173')
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept, Authorization, Token, X-Requested-With'
    response.headers['Access-Control-Allow-Credentials'] = 'true'
  end
  
  def record_not_found
    render json: { error: 'Record not found' }, status: :not_found
  end
  
  def record_invalid(exception)
    render json: { 
      error: 'Validation failed',
      details: exception.record.errors.full_messages 
    }, status: :unprocessable_entity
  end
  
  def token_expired
    render json: { error: 'Token expired' }, status: :unauthorized
  end
  
  def token_invalid
    render json: { error: 'Invalid token' }, status: :unauthorized
  end
end
