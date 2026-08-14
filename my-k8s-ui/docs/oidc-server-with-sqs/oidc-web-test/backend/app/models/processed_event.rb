# frozen_string_literal: true

# ----------------------------------------------------------------------------
# 冪等性(Idempotency)担保用のテーブル。
#
# SQSは「At-Least-Once(少なくとも1回)」配信のため、全く同じメッセージが
# 2回以上届く可能性がある。また、RESTアダプター経由でもクライアント側の
# リトライにより同一操作が重複しうる。
#
# event_id にユニーク制約を張り、UserSyncApplicationService が
# トランザクション内でこのレコードを作成しようとして一意制約違反になった
# 場合、それは「既に処理済みのイベント」であることが分かる
# (:skipped_duplicate を返す)。
# ----------------------------------------------------------------------------

class ProcessedEvent < ApplicationRecord
  validates :event_id, presence: true, uniqueness: true
end
