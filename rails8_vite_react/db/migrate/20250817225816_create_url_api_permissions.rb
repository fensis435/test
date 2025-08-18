class CreateUrlApiPermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :url_api_permissions do |t|
      t.string :url_pattern, null: false    # "users", "users/:id", "auth/login" など
      t.string :http_method, null: false    # "GET", "POST" など
      t.references :permission, null: false, foreign_key: true

      t.timestamps
    end
    add_index :url_api_permissions, [:url_pattern, :http_method, :permission_id]
  end
end
