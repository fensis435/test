# frozen_string_literal: true

# ----------------------------------------------------------------------------
# コアロジック。UserSyncUseCase(Port)の実装。
#
# 入力がSQS経由でもREST経由でも、必ずこのクラスの #sync_user_change だけを
# 通る。SQSのメッセージ形式・CloudTrailのJSON構造・HTTPパラメータの形状は
# 一切知らない(それらはAdapter層の責務)。
#
# 「実際に設計・実装する際の3つの注意点」のうち、以下2つをここで担保する:
#
#   2. 冪等性(Idempotency):
#      ProcessedEvent テーブルに event_id をユニーク制約で記録し、
#      重複したイベントはトランザクション内で確実にスキップする。
#
#   3. イベントの順序保証:
#      SyncedUser.source_event_time よりも古い event_time を持つ
#      イベントは無視する(新→古の順で届いても、古い方で上書きしない)。
#
# 1つ目の「同期/非同期のレスポンス設計」はこのクラスの外側
# (Adapter側)の責務であるため、ここでは扱わない
# (app/adapters/inbound/ の各Adapterのコメント参照)。
# ----------------------------------------------------------------------------

class UserSyncApplicationService
  include UserSyncUseCase

  DELETE_EVENT_NAMES = %w[AdminDeleteUser].freeze

  def sync_user_change(event)
    event.validate!

    ActiveRecord::Base.transaction do
      unless record_event_once(event)
        return :skipped_duplicate
      end

      existing = SyncedUser.find_by(external_user_id: event.user_id)

      if existing&.stale_event?(event.event_time)
        Rails.logger.info(
          "[UserSyncApplicationService] skipped stale event #{event.event_id} " \
          "(#{event.event_name}) for #{event.user_id}: " \
          "event_time=#{event.event_time.iso8601} <= source_event_time=#{existing.source_event_time&.iso8601}"
        )
        return :skipped_stale
      end

      apply_change(event, existing)

      :applied
    end
  end

  private

  # ProcessedEventの作成そのものを冪等性チェックとして使う。
  # 一意制約違反(ActiveRecord::RecordNotUnique)が発生したら、
  # 「既に処理済みのイベント」であることが確定する。
  #
  # @return [Boolean] true なら初回処理、false なら重複(既に処理済み)
  def record_event_once(event)
    ProcessedEvent.create!(event_id: event.event_id, event_name: event.event_name)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def apply_change(event, existing)
    if DELETE_EVENT_NAMES.include?(event.event_name)
      existing&.destroy!
      return
    end

    record = existing || SyncedUser.new(external_user_id: event.user_id)

    record.email = event.attributes["email"] if event.attributes.key?("email")
    record.given_name = event.attributes["given_name"] if event.attributes.key?("given_name")
    record.family_name = event.attributes["family_name"] if event.attributes.key?("family_name")
    record.status = event.attributes["status"] if event.attributes.key?("status")

    record.source_event_time = event.event_time
    record.source_event_name = event.event_name

    record.save!
  end
end
