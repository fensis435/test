class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string  :name
      t.string  :email
      t.string  :password_digest
      t.boolean :admin, default: false, null: false
      t.integer :logout_at, comment: "全ログアウトした時刻のUnixタイムスタンプ"

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :logout_at
    add_index :users, :admin
  end
end
