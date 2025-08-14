class User < ApplicationRecord
  has_secure_password
  has_many :blacklisted_tokens, dependent: :destroy
  has_many :user_sessions, dependent: :destroy
  
  validates :name, presence: true
  validates :name, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, if: :password_digest_changed?

  # 管理者フラグ（必要に応じてマイグレーションで追加）
  # validates :admin, inclusion: { in: [true, false] }

  scope :admins, -> { where(admin: true) }
  scope :regular_users, -> { where(admin: false) }
  
  # セッション作成
  def create_session(jti, token_type, exp, device_info = nil)
    user_sessions.create!(
      jti: jti,
      token_type: token_type,
      exp: exp,
      device_info: device_info
    )
  end

  # アクティブなセッション数
  def active_sessions_count
    user_sessions.active.count
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
end
