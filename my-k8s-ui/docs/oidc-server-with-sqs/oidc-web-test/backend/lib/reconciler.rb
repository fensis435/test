# frozen_string_literal: true

require_relative "../config/environment"

# ----------------------------------------------------------------------------
# 定期リコンサイルの常駐プロセス本体。bin/reconciler から起動される。
#
# SQSポーラー(lib/sqs_poller.rb)とは独立したプロセスとして動かす。
# 両者が同時にUserSyncApplicationServiceを呼び出しても、冪等性・
# 順序保証のガードはDBのトランザクション内で完結しているため、
# 競合による不整合は発生しない。
# ----------------------------------------------------------------------------

module Reconciler
  class << self
    def run_forever(interval_seconds: ENV.fetch("RECONCILE_INTERVAL_SECONDS", "300").to_i)
      adapter = ReconciliationAdapter.new
      @shutting_down = false

      trap("TERM") { @shutting_down = true }
      trap("INT") { @shutting_down = true }

      Rails.logger.info("[reconciler] starting. interval=#{interval_seconds}s")

      until @shutting_down
        begin
          adapter.run_once
        rescue StandardError => e
          Rails.logger.error("[reconciler] run failed: #{e.class}: #{e.message}")
        end

        # sleep(interval_seconds) を一度に呼ぶと、シグナル受信から
        # 実際にループを抜けるまでの応答が最大interval_seconds秒遅れうる。
        # 1秒刻みでチェックすることでシャットダウンの応答性を確保する。
        interval_seconds.times do
          break if @shutting_down

          sleep 1
        end
      end

      Rails.logger.info("[reconciler] shutting down gracefully")
    end
  end
end
