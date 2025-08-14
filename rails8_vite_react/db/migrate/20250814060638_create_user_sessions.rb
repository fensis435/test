class CreateUserSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :jti, null: false, comment: "JWT ID"
      t.string :token_type, null: false, comment: "access or refresh"
      t.integer :exp, null: false, comment: "トークンの有効期限 (Unix timestamp)"
      t.text :device_info, comment: "デバイス情報 (JSON)"
      t.string :ip_address, comment: "IPアドレス"
      t.datetime :last_used_at, comment: "最後に使用された時刻"

      t.timestamps
    end

    add_index :user_sessions, :jti, unique: true
    add_index :user_sessions, [:user_id, :token_type]
    add_index :user_sessions, :exp
    add_index :user_sessions, [:user_id, :exp]
  end
end
