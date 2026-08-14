# frozen_string_literal: true

class CreateSyncedUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :synced_users do |t|
      # Cognitoのusername(=sub)、または oidc-dev-server の Users.id。
      # 「外部の」ユーザーDB(IdP側)における一意識別子であることを
      # 明示するため external_user_id という名前にしている
      # (このテーブル自身のPKであるidとは別物)。
      t.string :external_user_id, null: false
      t.string :email
      t.string :given_name
      t.string :family_name
      t.string :status # "ACTIVE" | "DISABLED"

      # 順序保証(古いイベントで新しい状態を上書きしない)に使う。
      # イベント側(CloudTrail eventTime)のタイムスタンプであり、
      # このレコード自体のupdated_atとは別に保持する。
      t.datetime :source_event_time
      t.string :source_event_name

      t.timestamps
    end

    add_index :synced_users, :external_user_id, unique: true
  end
end
