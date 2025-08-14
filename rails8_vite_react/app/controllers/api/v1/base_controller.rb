class Api::V1::BaseController < Api::BaseController
  before_action :authenticate_user
  before_action :set_api_version

  private

  def set_api_version
    response.headers['API-Version'] = 'v1'
  end

  def current_user
    @current_user
  end

  def authenticate_user!
    token = extract_token
    return render_unauthorized('Token missing') unless token

    begin
      decoded = JWT.decode(token, jwt_secret).first
      @current_user = User.find(decoded['user_id'])
    rescue JWT::ExpiredSignature
      render_unauthorized('Token expired')
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render_unauthorized('Invalid token')
    end
  end

  def authenticate_user
    authenticate_user!
  end

  def extract_token
    request.headers['Authorization']&.split(' ')&.last
  end

  def jwt_secret
    Rails.application.credentials.secret_key_base || Rails.application.secrets.secret_key_base
  end

  def render_unauthorized(message = 'Unauthorized')
    render json: { error: message }, status: :unauthorized
  end

  def authenticated?
    current_user.present?
  end

  def admin?
    authenticated? && current_user.admin?
  end
end
