class UserSession < ApplicationRecord
  belongs_to :user

  validates :jti, presence: true, uniqueness: true
  validates :token_type, presence: true, inclusion: { in: %w[access refresh] }
  validates :exp, presence: true
  validates :device_info, length: { maximum: 500 }

  scope :active, -> { where('exp >= ?', Time.current.to_i) }
  scope :expired, -> { where('exp < ?', Time.current.to_i) }
  scope :access_tokens, -> { where(token_type: 'access') }
  scope :refresh_tokens, -> { where(token_type: 'refresh') }

  def expired?
    Time.current.to_i >= exp
  end

  def self.cleanup_expired
    expired.delete_all
  end
end
