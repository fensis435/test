class User < ApplicationRecord
  has_secure_password
  has_many :blacklisted_tokens, dependent: :destroy
  has_many :user_sessions, dependent: :destroy
  has_many :user_permissions, dependent: :destroy
  has_many :permissions, through: :user_permissions
  
  validates :name, presence: true
  validates :name, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, if: :password_digest_changed?

  # 管理者フラグ（必要に応じてマイグレーションで追加）
  # validates :admin, inclusion: { in: [true, false] }

  scope :admins, -> { where(admin: true) }
  scope :regular_users, -> { where(admin: false) }

  enum :app_status, {
    not_deployed: 'not_deployed',
    running:      'running',
    stopped:      'stopped',
    starting:     'starting',
    error:        'error'
  }

  scope :with_running_apps, -> { where(app_status: 'running') }
  scope :with_deployed_apps, -> { where.not(app_status: 'not_deployed') }
  scope :session_expired, ->(timeout_minutes = 30) {
    where('last_login_at < ?', timeout_minutes.minutes.ago)
  }
  
  # セッション作成
  def create_session(jti, token_type, exp, device_info = nil)
    user_sessions.create!(
      jti: jti,
      token_type: token_type,
      exp: exp,
      device_info: device_info
    )
  end

  def dstroy_session(jti)
    user_sessions.where(jti: jti).destroy_all
  end

  # アクティブなセッション数
  def active_sessions_count
    user_sessions.active.count
  end

  # 権限チェックメソッド
  def has_permission?(permission_name)
    permissions.exists?(name: permission_name)
  end

  def has_any_permission?(permission_names)
    permissions.where(name: permission_names).exists?
  end

  def has_role?(role_name)
    permissions.by_role(role_name).exists?
  end

  def has_access_level?(access_level)
    permissions.by_access_level(access_level).exists?
  end

  # URL-based API実行権限チェック
  def can_access_url?(url_path, http_method)
    required_permissions = UrlBasedApiPermissionService.required_permissions_for_url(url_path, http_method)
    
    return true if required_permissions.empty? # 権限設定がない場合は許可
    return true if permissions.where(name: UrlBasedApiPermissionService.system_administrator_permission).exists?
    
    has_any_permission?(required_permissions)
  end

  # レガシー: controller/action ベースの権限チェック（互換性のため残す）
  def can_access_api?(controller_name, action_name, http_method)
    # URLベースに変換してチェック
    url_path = convert_controller_action_to_url(controller_name, action_name)
    can_access_url?(url_path, http_method)
  end

  # 権限追加/削除メソッド
  def add_permission(permission_name)
    permission = Permission.find_by(name: permission_name)
    return false unless permission
    
    user_permissions.find_or_create_by(permission: permission)
    true
  end

  def remove_permission(permission_name)
    permission = Permission.find_by(name: permission_name)
    return false unless permission
    
    user_permissions.where(permission: permission).destroy_all
    true
  end

  # 既存のroleとの互換性維持（移行期間用）
  def legacy_role_permissions
    case role
    when 'admin'
      ['system:admin', 'admin:read', 'admin:write', 'users:admin', 'maintenance:admin']
    when 'manager'
      ['manager:read', 'manager:write', 'users:read', 'users:write', 'apps:read', 'apps:write']
    when 'regular'
      ['profile:read', 'profile:write']
    else
      []
    end
  end

  private

  # 管理者かどうか
  def admin?
    # adminカラムがある場合
    respond_to?(:admin) ? admin : false
  end
  
  def jwt_secret
    Rails.application.credentials.secret_key_base || Rails.application.secrets.secret_key_base
  end

  def convert_controller_action_to_url(controller_name, action_name)
    # コントローラー名とアクション名からURLパスを推定
    case "#{controller_name}##{action_name}"
    when 'users#index' then 'users'
    when 'users#show' then 'users/:id'
    when 'users#create' then 'users'
    when 'users#update' then 'users/:id'
    when 'users#destroy' then 'users/:id'
    when 'users#me' then 'users/me'
    when 'users#search' then 'users/search'
    when 'users#change_password' then 'users/:id/change_password'
    when 'users#sessions' then 'users/:id/sessions'
    when 'auth#login' then 'auth/login'
    when 'auth#refresh' then 'auth/refresh'
    when 'auth#logout' then 'auth/logout'
    when 'auth#logout_all' then 'auth/logout_all'
    when 'auth#me' then 'auth/me'
    when 'auth#sessions' then 'auth/sessions'
    when 'permissions#index' then 'permissions'
    when 'permissions#create' then 'permissions'
    when 'permissions#update' then 'permissions/:id'
    when 'permissions#destroy' then 'permissions/:id'
    else
      # デフォルトのRESTfulな変換
      case action_name
      when 'index', 'create' then controller_name
      when 'show', 'update', 'destroy' then "#{controller_name}/:id"
      else "#{controller_name}/#{action_name}"
      end
    end
  end

end
