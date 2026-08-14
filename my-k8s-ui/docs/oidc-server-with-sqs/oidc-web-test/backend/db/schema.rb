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

ActiveRecord::Schema[8.1].define(version: 2026_01_01_000002) do
  create_table "processed_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_id", null: false
    t.string "event_name"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_processed_events_on_created_at"
    t.index ["event_id"], name: "index_processed_events_on_event_id", unique: true
  end

  create_table "synced_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "external_user_id", null: false
    t.string "family_name"
    t.string "given_name"
    t.string "source_event_name"
    t.datetime "source_event_time"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["external_user_id"], name: "index_synced_users_on_external_user_id", unique: true
  end
end
