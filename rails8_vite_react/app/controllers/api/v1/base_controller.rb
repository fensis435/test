class Api::V1::BaseController < Api::BaseController
  before_action :authenticate_request
  before_action :set_api_version
  attr_reader :current_user, :current_token

  private

  def set_api_version
    response.headers['API-Version'] = 'v1'
  end

  def authenticate_request
    result = AuthorizeApiRequest.new(request.headers).call
    if result
      @current_user = result[:user]
      @current_token = result[:token_data]
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
    authenticated? && current_user.admin?
  end
end
