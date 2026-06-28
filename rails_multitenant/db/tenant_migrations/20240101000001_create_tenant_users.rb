class CreateTenantUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users, id: :uuid do |t|
      t.string :cognito_sub, null: false
      t.string :email, null: false
      t.string :display_name
      t.string :role, null: false, default: "member"
      t.datetime :deactivated_at
      t.timestamps
    end

    add_index :users, :cognito_sub, unique: true
    add_index :users, :email, unique: true
    add_index :users, :role
    add_index :users, :deactivated_at
  end
end
