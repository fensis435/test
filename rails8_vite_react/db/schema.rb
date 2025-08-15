# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_14_060638) do
  create_table "blacklisted_tokens", force: :cascade do |t|
    t.string "jti", null: false
    t.integer "exp", null: false
    t.integer "user_id"
    t.text "reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exp"], name: "index_blacklisted_tokens_on_exp"
    t.index ["jti"], name: "index_blacklisted_tokens_on_jti", unique: true
    t.index ["user_id", "exp"], name: "index_blacklisted_tokens_on_user_id_and_exp"
    t.index ["user_id"], name: "index_blacklisted_tokens_on_user_id"
  end

  create_table "user_sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "jti", null: false
    t.string "token_type", null: false
    t.integer "exp", null: false
    t.text "device_info"
    t.string "ip_address"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["exp"], name: "index_user_sessions_on_exp"
    t.index ["jti"], name: "index_user_sessions_on_jti", unique: true
    t.index ["user_id", "exp"], name: "index_user_sessions_on_user_id_and_exp"
    t.index ["user_id", "token_type"], name: "index_user_sessions_on_user_id_and_token_type"
    t.index ["user_id"], name: "index_user_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.string "password_digest"
    t.string "role", default: "regular", null: false
    t.integer "logout_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["logout_at"], name: "index_users_on_logout_at"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "blacklisted_tokens", "users"
  add_foreign_key "user_sessions", "users"
end
