class CreateTenants < ActiveRecord::Migration[8.0]
  def change
    create_table :tenants, id: :uuid do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :status, null: false, default: "provisioning"
      t.string :plan, null: false, default: "free"
      t.jsonb :settings, null: false, default: {}
      t.jsonb :database_config
      t.datetime :suspended_at
      t.timestamps
    end

    add_index :tenants, :slug, unique: true
    add_index :tenants, :status
    add_index :tenants, :plan
    add_index :tenants, :created_at
    add_index :tenants, "settings", using: :gin
  end
end
