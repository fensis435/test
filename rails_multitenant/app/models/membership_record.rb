class MembershipRecord < ApplicationRecord
  self.table_name = "memberships"

  VALID_ROLES = %w[owner admin member viewer].freeze

  belongs_to :user, class_name: "UserRecord", foreign_key: :user_id

  validates :user_id, presence: true
  validates :role, inclusion: { in: VALID_ROLES }
  validates :user_id, uniqueness: true

  scope :by_role, ->(role) { where(role: role) }
end
