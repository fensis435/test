# frozen_string_literal: true

# ----------------------------------------------------------------------------
# Port(駆動ポート / Primary Port)。
#
# 入力アダプター(SqsUserEventAdapter, RestUserEventAdapter等)が呼び出す
# 唯一の入り口。アダプターは自分の入力形式(SQSメッセージ、HTTPパラメータ等)
# を UserChangeEvent に変換しさえすれば、入力元がSQSでもRESTでも
# 同じコアロジック(UserSyncApplicationService)に到達する。
#
# Rubyは構造的型付けを持たないため、この module は「契約のドキュメント化」
# としての意味が主だが、`include UserSyncUseCase` した実装クラスが
# #sync_user_change を実装し忘れた場合に NotImplementedError で
# 気づけるようにする効果もある。
# ----------------------------------------------------------------------------

module UserSyncUseCase
  # @param event [UserChangeEvent]
  # @return [Symbol] :applied | :skipped_duplicate | :skipped_stale
  def sync_user_change(event)
    raise NotImplementedError, "#{self.class} must implement #sync_user_change"
  end
end
