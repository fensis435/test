class Permission < ApplicationRecord
  has_many :user_permissions, dependent: :destroy
  has_many :users, through: :user_permissions
  has_many :url_api_permissions, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :name, format: { with: /\A[a-z_]+:(read|write|admin)\z/, 
                            message: "must be in format 'role:access' (e.g., 'manager:read')" }

  scope :by_role, ->(role) { where("name LIKE ?", "#{role}:%") }
  scope :by_access_level, ->(level) { where("name LIKE ?", "%:#{level}") }

  def role
    name.split(':').first
  end

  def access_level
    name.split(':').last
  end
end
