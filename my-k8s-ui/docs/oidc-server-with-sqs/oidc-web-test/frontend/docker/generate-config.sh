#!/bin/sh
set -eu

# ----------------------------------------------------------------------------
# コンテナ起動時に環境変数から config.js を動的生成する。
# Node.js/npm/viteは一切使わず、シェルの範囲で完結させることで
# 「実行時にNode.jsを一切動かさない」という運用方針を維持する。
#
# Helm/K8sのConfigMap経由でこのスクリプトに渡す環境変数を切り替えるだけで、
# 同一のDockerイメージを dev/staging/本番すべてで使い回せる。
#
# 出力先は静的アセットの配信ルート直下(Railsの public/ 等、実際の配置に
# 合わせて OUTPUT_DIR を調整すること)。
# ----------------------------------------------------------------------------

OUTPUT_DIR="${STATIC_ASSETS_DIR:-/app/public}"
OUTPUT_FILE="${OUTPUT_DIR}/config.js"

: "${OIDC_ISSUER:?OIDC_ISSUER is required}"
: "${OIDC_CLIENT_ID:?OIDC_CLIENT_ID is required}"
: "${OIDC_REDIRECT_URI:?OIDC_REDIRECT_URI is required}"
: "${OIDC_POST_LOGOUT_REDIRECT_URI:?OIDC_POST_LOGOUT_REDIRECT_URI is required}"
: "${RAILS_API_BASE_URL:?RAILS_API_BASE_URL is required}"

OIDC_SCOPES="${OIDC_SCOPES:-openid email profile groups offline_access}"

cat > "$OUTPUT_FILE" <<EOF
// このファイルはビルド成果物ではない。コンテナ起動時に
// docker/generate-config.sh によって自動生成される。手動編集しないこと。
window.__APP_CONFIG__ = {
  OIDC_ISSUER: "${OIDC_ISSUER}",
  OIDC_CLIENT_ID: "${OIDC_CLIENT_ID}",
  OIDC_REDIRECT_URI: "${OIDC_REDIRECT_URI}",
  OIDC_POST_LOGOUT_REDIRECT_URI: "${OIDC_POST_LOGOUT_REDIRECT_URI}",
  OIDC_SCOPES: "${OIDC_SCOPES}",
  RAILS_API_BASE_URL: "${RAILS_API_BASE_URL}"
};
EOF

echo "[generate-config] Wrote runtime config to ${OUTPUT_FILE}"
