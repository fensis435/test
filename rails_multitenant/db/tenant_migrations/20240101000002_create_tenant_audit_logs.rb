class CreateTenantAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs, id: :uuid do |t|
      t.string :tenant_id, null: false
      t.string :actor_sub, null: false
      t.string :actor_email, null: false
      t.string :actor_role
      t.string :action, null: false
      t.string :resource_type
      t.string :resource_id
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address
      t.string :user_agent
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :audit_logs, :tenant_id
    add_index :audit_logs, :actor_sub
    add_index :audit_logs, :action
    add_index :audit_logs, [:resource_type, :resource_id]
    add_index :audit_logs, :occurred_at
    add_index :audit_logs, "metadata", using: :gin

    # Partition by month for large-scale audit log retention
    # In production, use pg_partman for automatic partition management
  end
end
