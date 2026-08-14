# frozen_string_literal: true

class CreateProcessedEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :processed_events do |t|
      t.string :event_id, null: false
      t.string :event_name

      t.timestamps
    end

    add_index :processed_events, :event_id, unique: true

    # 冪等性チェック用テーブルが無限に肥大化しないよう、古いレコードを
    # 定期的にパージする運用を前提とする(created_atでの範囲削除を想定)。
    add_index :processed_events, :created_at
  end
end
