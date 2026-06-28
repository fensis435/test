class CreateTenantMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :memberships, id: :uuid do |t|
      t.references :user, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :role, null: false, default: "member"
      t.string :invited_by
      t.timestamps
    end

    add_index :memberships, :user_id, unique: true
    add_index :memberships, :role
  end
end
