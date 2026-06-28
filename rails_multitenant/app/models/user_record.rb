class UserRecord < ApplicationRecord
  self.table_name = "users"

  VALID_ROLES = %w[owner admin member viewer].freeze

  validates :cognito_sub, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: VALID_ROLES }

  scope :by_role, ->(role) { where(role: role) }
  scope :active, -> { where(deactivated_at: nil) }
  scope :search, ->(q) { where("email ILIKE ? OR display_name ILIKE ?", "%#{sanitize_sql_like(q)}%", "%#{sanitize_sql_like(q)}%") }

  def active?
    deactivated_at.nil?
  end

  def deactivate!
    update!(deactivated_at: Time.current)
  end
end
