# frozen_string_literal: true

require_relative "../config/environment"

# ----------------------------------------------------------------------------
# SQSポーリングの常駐プロセス本体。
#
# bin/sqs_poller から起動される。ロングポーリング(wait_time_seconds: 10)を
# 使っているため、メッセージが無い間はSQS側で待機し、CPUを無駄に消費しない。
#
# K8sで運用する場合はDeployment(replicas: 1を推奨。複数レプリカでも
# SQSの可視性タイムアウトにより二重処理は原理的に起きないが、
# 冪等性ガードに頼りきらず単純さを優先するため)として動かすことを想定。
# このリポジトリではdocker-compose上のワンショットではなく常駐サービスとして
# 動かす想定のため、SIGTERM/SIGINTでのグレースフルシャットダウンに対応する。
# ----------------------------------------------------------------------------

module SqsPoller
  class << self
    def run_forever
      adapter = SqsUserEventAdapter.new
      @shutting_down = false

      trap("TERM") { @shutting_down = true }
      trap("INT") { @shutting_down = true }

      Rails.logger.info("[sqs_poller] starting poll loop against #{ENV['SQS_QUEUE_URL']}")

      until @shutting_down
        begin
          count = adapter.poll_once
          Rails.logger.debug("[sqs_poller] processed #{count} messages") if count.positive?
        rescue StandardError => e
          # ポーリング自体(ネットワークエラー等)が失敗しても、プロセス全体を
          # 落とさずリトライを続ける。個々のメッセージ処理エラーは
          # SqsUserEventAdapter 内で既にハンドリング済み。
          Rails.logger.error("[sqs_poller] poll_once failed: #{e.class}: #{e.message}")
          sleep 5
        end
      end

      Rails.logger.info("[sqs_poller] shutting down gracefully")
    end
  end
end
