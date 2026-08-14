// ----------------------------------------------------------------------------
// [設計変更] Viteの import.meta.env.VITE_* はビルド時に値がJSへ
// ハードコードされるため、「1つのDockerイメージを全環境(dev/staging/
// 本番)で使い回し、Helm/K8sのConfigMapで環境ごとの値を注入する」という
// 運用ができない。
//
// 代わりに、index.html が読み込まれた直後に <script src="/config.js"> で
// 別ファイルを読み込ませ、そこで window.__APP_CONFIG__ にランタイム値を
// 注入する方式にする。config.js自体はビルド成果物に含めず、コンテナ起動時
// (entrypointスクリプト)に環境変数から動的生成する。
//
// これにより:
//   - Dockerイメージは1回ビルドすれば全環境で使い回せる
//   - ランタイムにNode.js/vite buildが一切不要(envsubst等の軽量な
//     テキスト置換で済む)
//   - Helm values / K8s ConfigMap経由でこれまで通り環境ごとの値を注入できる
// ----------------------------------------------------------------------------

export interface AppRuntimeConfig {
  OIDC_ISSUER: string;
  OIDC_CLIENT_ID: string;
  OIDC_REDIRECT_URI: string;
  OIDC_POST_LOGOUT_REDIRECT_URI: string;
  OIDC_SCOPES?: string;
  RAILS_API_BASE_URL: string;
}

declare global {
  interface Window {
    __APP_CONFIG__?: AppRuntimeConfig;
  }
}

/**
 * ランタイム設定を取得する。
 *
 * 優先順位:
 *   1. window.__APP_CONFIG__ (config.js経由、コンテナ起動時に注入される値。本番/Helm運用時)
 *   2. import.meta.env.VITE_* (ローカル開発時、`npm run dev`でVite自体が.envを読む場合のフォールバック)
 *
 * ローカル開発(`vite dev`実行時)は今まで通り `.env` で完結させたいという
 * 声を尊重し、フォールバックとして import.meta.env も残してある。
 * 本番/Helm運用ではフォールバックに頼らないよう、config.js側で全項目を
 * 必ず埋めること(entrypoint/generate-config.shの実装を参照)。
 */
export function getRuntimeConfig(): AppRuntimeConfig {
  if (window.__APP_CONFIG__) {
    return window.__APP_CONFIG__;
  }

  // フォールバック(ローカル開発時のみ想定)
  return {
    OIDC_ISSUER: import.meta.env.VITE_OIDC_ISSUER,
    OIDC_CLIENT_ID: import.meta.env.VITE_OIDC_CLIENT_ID,
    OIDC_REDIRECT_URI: import.meta.env.VITE_OIDC_REDIRECT_URI,
    OIDC_POST_LOGOUT_REDIRECT_URI: import.meta.env.VITE_OIDC_POST_LOGOUT_REDIRECT_URI,
    OIDC_SCOPES: import.meta.env.VITE_OIDC_SCOPES,
    RAILS_API_BASE_URL: import.meta.env.VITE_RAILS_API_BASE_URL,
  };
}
