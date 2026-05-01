#!/bin/bash
# =============================================================================
# docker-entrypoint-rails.sh
# Rails アプリ起動前処理: DB接続確認 → migration → サーバ起動
# =============================================================================
set -e

log() { echo "[entrypoint] $*"; }

# ---------------------------------------------------------------------------
# Secrets Manager / 環境変数の解決
# ---------------------------------------------------------------------------
resolve_secrets() {
  # AWS Secrets Manager から DB接続情報を取得 (IRSA使用)
  if [ -n "${DB_SECRET_ARN:-}" ]; then
    log "Secrets Manager から DB認証情報を取得..."
    DB_CREDENTIALS=$(aws secretsmanager get-secret-value \
      --secret-id "${DB_SECRET_ARN}" \
      --query SecretString --output text 2>/dev/null || echo "{}")
    export DATABASE_USERNAME=$(echo "${DB_CREDENTIALS}" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('username',''))" 2>/dev/null || echo "")
    export DATABASE_PASSWORD=$(echo "${DB_CREDENTIALS}" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('password',''))" 2>/dev/null || echo "")
  fi

  # Cognito クライアントシークレット取得
  if [ -n "${COGNITO_SECRET_ARN:-}" ]; then
    log "Cognito クライアントシークレット取得..."
    COGNITO_SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "${COGNITO_SECRET_ARN}" \
      --query SecretString --output text 2>/dev/null || echo "{}")
    export COGNITO_CLIENT_SECRET=$(echo "${COGNITO_SECRET}" | python3 -c \
      "import sys,json; d=json.load(sys.stdin); print(d.get('clientSecret',''))" 2>/dev/null || echo "")
  fi
}

# ---------------------------------------------------------------------------
# DB 接続確認 (RDS Proxy経由)
# ---------------------------------------------------------------------------
wait_for_database() {
  log "DB接続待機中 (${DATABASE_HOST:-localhost}:${DATABASE_PORT:-5432})..."
  local max_attempts=30
  local attempt=0

  until bundle exec rails db:version > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "${attempt}" -ge "${max_attempts}" ]; then
      log "ERROR: DB接続タイムアウト (${max_attempts}回試行)"
      exit 1
    fi
    log "DB接続待機 (${attempt}/${max_attempts})..."
    sleep 5
  done
  log "DB接続成功"
}

# ---------------------------------------------------------------------------
# DB Migration (リーダーPodのみ実行)
# ---------------------------------------------------------------------------
run_migrations() {
  # POD_NAME が "-0" で終わる場合のみmigration実行 (StatefulSet想定)
  # Deployment の場合は MIGRATION_RUNNER=true 環境変数で制御
  if [ "${MIGRATION_RUNNER:-false}" = "true" ]; then
    log "DB migration 実行中..."
    bundle exec rails db:migrate
    log "DB migration 完了"
  else
    log "Migration スキップ (MIGRATION_RUNNER != true)"
  fi
}

# ---------------------------------------------------------------------------
# Puma の pid ファイルクリーンアップ
# ---------------------------------------------------------------------------
cleanup_pid() {
  if [ -f tmp/pids/server.pid ]; then
    log "古いPIDファイルを削除..."
    rm -f tmp/pids/server.pid
  fi
}

# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------
log "Rails アプリ起動開始 (RAILS_ENV=${RAILS_ENV:-production})"

resolve_secrets
wait_for_database
run_migrations
cleanup_pid

log "Puma 起動: $*"
exec "$@"
