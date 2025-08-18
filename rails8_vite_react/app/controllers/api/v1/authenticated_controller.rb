class Api::V1::AuthenticatedController < Api::V1::BaseController
  before_action :authenticate_user
  attr_reader :current_user, :current_token
  
  private
  
  def authenticate_user
    token = extract_token
    return render_unauthorized('Token missing') unless token

    begin
      decoded = JWT.decode(token, jwt_secret).first
      @current_user = User.find(decoded['user_id'])
    rescue ActiveRecord::RecordNotFound
      render_unauthorized('User not found')
    end
  end

  def current_user
    @current_user
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
end
