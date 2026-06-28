class AuditLog < ApplicationRecord
  self.table_name = "audit_logs"

  validates :action, presence: true
  validates :actor_sub, presence: true
  validates :actor_email, presence: true
  validates :tenant_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :by_actor, ->(sub) { where(actor_sub: sub) }

  def self.record(tenant:, actor:, action:, resource_type: nil, resource_id: nil, metadata: {})
    create!(
      tenant_id: tenant.id,
      actor_sub: actor.sub,
      actor_email: actor.email,
      actor_role: actor.role,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata,
      occurred_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("AuditLog record failed: #{e.message} action=#{action}")
    nil
  end
end
