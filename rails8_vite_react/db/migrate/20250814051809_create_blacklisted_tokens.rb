class CreateBlacklistedTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :blacklisted_tokens do |t|
      t.string :jti, null: false, comment: "JWT ID (unique identifier)"
      t.integer :exp, null: false, comment: "トークンの有効期限 (Unix timestamp)"
      t.references :user, null: true, foreign_key: true, comment: "トークンの所有者 (optional)"
      t.text :reason, comment: "ブラックリストに追加した理由"

      t.timestamps
    end

    add_index :blacklisted_tokens, :jti, unique: true
    add_index :blacklisted_tokens, :exp
    add_index :blacklisted_tokens, [:user_id, :exp]
  end
end
