module UrlBasedRbacAuthorization
  extend ActiveSupport::Concern

  included do
    before_action :check_url_permission, except: []
  end

  private

  def check_url_permission
    return if skip_authorization?
    
    unless current_user&.can_access_url?(current_api_path, request.method)
      render_authorization_error
    end
  end

  def skip_authorization?
    # 認証が不要なエンドポイント
    return true if controller_name == 'health'
    return true if public_endpoint?
    return true if authentication_endpoints?
    
    false
  end

  def authentication_endpoints?
    # 認証関連のエンドポイントは権限チェックをスキップ
    api_path = current_api_path
    api_path == 'auth/login' || api_path == 'auth/refresh'
  end

  def public_endpoint?
    # パブリックエンドポイントの定義
    api_path = current_api_path
    api_path.start_with?('public/') ||
    (controller_name == 'frontend' && Rails.env.development?)
  end

  def current_api_path
    # /api/v1/users/123 -> users/123
    # /api/v1/auth/login -> auth/login
    path = request.path
    path.gsub(%r{^/?api/v1/?}, '').gsub(%r{^/+|/+$}, '')
  end

  def render_authorization_error
    api_path = current_api_path
    required_perms = get_required_permissions_for_url(api_path, request.method)
    
    render json: {
      error: 'Insufficient permissions',
      message: 'You do not have the required permissions to access this resource',
      url: api_path,
      method: request.method,
      required_permissions: required_perms,
      your_permissions: current_user&.permissions&.pluck(:name) || []
    }, status: :forbidden
  end

  def get_required_permissions_for_url(url_path, http_method)
    UrlBasedApiPermissionService.required_permissions_for_url(url_path, http_method)
  end
end
