# frozen_string_literal: true

# ----------------------------------------------------------------------------
# Cognito(本番)またはoidc-dev-server(開発、CloudTrail/EventBridge/SQS
# パイプラインのシミュレーション経由)から同期される「仮の」ユーザーDB。
#
# 実際のオンプレ本番実装では、WebGUIからのREST API操作で直接書き込まれる
# 既存のユーザーDBがこれに相当する。このアプリではその代替として最小限の
# テーブルを用意している。
# ----------------------------------------------------------------------------

class SyncedUser < ApplicationRecord
  validates :external_user_id, presence: true, uniqueness: true

  # サーバー側(Cognito/oidc-dev-server)から見た「まだ反映していない古い
  # イベントで上書きしていないか」の判定に使う。UserSyncApplicationService
  # 参照。
  def stale_event?(event_time)
    source_event_time.present? && event_time <= source_event_time
  end
end
