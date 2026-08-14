# frozen_string_literal: true

# ----------------------------------------------------------------------------
# 最優先要件(Cognito Hosted UI置き換え時のRailsコード変更最小化)に対応。
# OIDC_ISSUERをCognito User PoolのURLに切り替えるだけで、TokenVerifierは
# Discoveryドキュメント経由でjwks_uri等を自動解決し直す(URLのハードコード
# はしていない。app/services/token_verifier.rb 参照)。
# ----------------------------------------------------------------------------

Rails.application.config.x.oidc.issuer = ENV.fetch("OIDC_ISSUER", "http://localhost:3000")
