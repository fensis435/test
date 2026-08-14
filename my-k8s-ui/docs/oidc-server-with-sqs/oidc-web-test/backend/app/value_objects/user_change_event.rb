# frozen_string_literal: true

# ----------------------------------------------------------------------------
# 入力経路(REST / SQS)に依存しない、共通のユーザー変更イベント構造。
#
# 「入力元の差異はAdapter層で吸収する」というPorts and Adaptersの原則に
# 従い、RestUserEventAdapter・SqsUserEventAdapter は共にこの構造に変換
# してから UserSyncUseCase(Port)を呼ぶ。UserSyncApplicationService(コア
# ロジック)はこの構造だけを知っていればよく、SQSやCloudTrailの生JSON形式
# を一切知らない。
# ----------------------------------------------------------------------------

UserChangeEvent = Struct.new(
  :event_id,   # String: 冪等性キー(同じevent_idの再処理はスキップされる)
  :event_name, # String: "AdminCreateUser" 等、Cognito Admin API名で統一する
  :user_id,    # String: 対象ユーザーの一意識別子(Cognitoのusername/sub相当)
  :event_time, # Time: イベント発生時刻。順序保証(古いイベントの無視)に使う
  :attributes, # Hash: email, given_name, family_name, status, group_id 等
  keyword_init: true
) do
  def validate!
    raise ArgumentError, "event_id is required" if event_id.to_s.empty?
    raise ArgumentError, "event_name is required" if event_name.to_s.empty?
    raise ArgumentError, "user_id is required" if user_id.to_s.empty?
    raise ArgumentError, "event_time must be a Time" unless event_time.is_a?(Time)

    self
  end
end
