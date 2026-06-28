class TenantRecord < ApplicationRecord
  self.table_name = "tenants"

  VALID_STATUSES = %w[provisioning active suspended terminated].freeze
  VALID_PLANS = %w[free starter professional enterprise].freeze

  validates :slug, presence: true, uniqueness: { case_sensitive: false },
            format: { with: /\A[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]\z/ }
  validates :name, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: VALID_STATUSES }
  validates :plan, inclusion: { in: VALID_PLANS }

  before_validation :normalize_slug

  scope :active, -> { where(status: "active") }
  scope :suspended, -> { where(status: "suspended") }
  scope :provisioning, -> { where(status: "provisioning") }
  scope :by_plan, ->(plan) { where(plan: plan) }
  scope :created_after, ->(date) { where("created_at >= ?", date) }
  scope :search_by_name, ->(query) { where("name ILIKE ?", "%#{sanitize_sql_like(query)}%") }

  private

  def normalize_slug
    self.slug = slug&.downcase&.strip
  end
end
