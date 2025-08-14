class BlacklistedToken < ApplicationRecord
  belongs_to :user, optional: true

  validates :jti, presence: true, uniqueness: true
  validates :exp, presence: true

  scope :expired, -> { where('exp < ?', Time.current.to_i) }
  scope :active, -> { where('exp >= ?', Time.current.to_i) }

  # 期限切れのトークンを削除するクリーンアップメソッド
  def self.cleanup_expired
    expired.delete_all
  end

  # 特定のJTIがブラックリストに登録されているかチェック
  def self.blacklisted?(jti)
    active.exists?(jti: jti)
  end

  # トークンをブラックリストに追加
  def self.blacklist_token(jti, exp, user_id = nil)
    create!(jti: jti, exp: exp, user_id: user_id)
  rescue ActiveRecord::RecordNotUnique
    # 既に存在する場合は無視
  end
end
