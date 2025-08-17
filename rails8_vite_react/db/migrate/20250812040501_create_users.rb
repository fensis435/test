class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string    :name
      t.string    :email
      t.string    :password_digest
      t.string    :role, default: "regular", null: false
      t.integer   :logout_at, comment: "全ログアウトした時刻のUnixタイムスタンプ"

      t.string    :k8s_namespace
      t.string    :k8s_release_name
      t.string    :app_url
      t.string    :app_status, default: 'not_deployed'
      t.timestamp :last_login_at, :timestamp

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :logout_at
    add_index :users, :role
    add_index :users, :k8s_namespace
    add_index :users, :app_status
    add_index :users, :last_login_at
  end
end
