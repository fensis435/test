module ApiAuthorization
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user, :current_token
    before_action :authenticate_request
    before_action :check_token_blacklist
    before_action :update_last_used
    include UrlBasedRbacAuthorization
  end

  private

  def authenticate_request
    result = AuthorizeApiRequest.new(request.headers).call
    if result
      @current_user = result[:user]
      @current_token = result[:token_data]
      @current_jti = @current_token['jti']
      render json: { error: 'Not Authorized' }, status: 401 unless @current_user
    else
      render json: { error: 'Not Authorized' }, status: 401
    end
  end

  def current_user
    @current_user
  end

  def authenticate_user
    authenticate_request
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
    authenticated? && (current_user.role == "admin")
  end

  def check_token_blacklist
    return unless @current_jti

    if TokenBlacklistService.blacklisted?(@current_jti)
      if BlacklistedToken.exists?(jti: @current_jti)
        render json: { error: 'Token has been blacklisted' }, status: :unauthorized
      end
    end
  end

  def update_last_used
    return unless @current_user && @current_jti

    session = UserSession.find_by(jti: @current_jti)
    session&.update(
      last_used_at: Time.current,
      ip_address: request.remote_ip
    )
  end

end
