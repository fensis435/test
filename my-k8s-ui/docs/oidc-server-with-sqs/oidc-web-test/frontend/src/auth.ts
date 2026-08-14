import { UserManager, WebStorageStateStore, type UserManagerSettings } from "oidc-client-ts";
import { getRuntimeConfig } from "./runtime-config";

// ----------------------------------------------------------------------------
// 最優先要件(Cognito Hosted UI置き換え時のReact/Railsコード変更最小化)を
// 反映した設定。
//
// `authority`(issuer)だけを環境変数で切り替えれば、authorize/token/jwks
// 等の個々のエンドポイントURLはoidc-client-tsがDiscoveryドキュメント経由で
// 自動解決する。個々のURLをここにハードコードしていないのはそのため。
//
// [変更] 値の取得元を import.meta.env から getRuntimeConfig() に変更。
// Vite特有のビルド時埋め込みに依存せず、config.js経由でコンテナ起動時に
// 注入されたランタイム値を使う(詳細は runtime-config.ts / entrypoint参照)。
// ----------------------------------------------------------------------------

const config = getRuntimeConfig();

const settings: UserManagerSettings = {
  authority: config.OIDC_ISSUER,
  client_id: config.OIDC_CLIENT_ID,
  redirect_uri: config.OIDC_REDIRECT_URI,
  post_logout_redirect_uri: config.OIDC_POST_LOGOUT_REDIRECT_URI,
  response_type: "code",
  scope: config.OIDC_SCOPES ?? "openid email profile groups offline_access",
  // 検証用トップページのみのため、複雑なsilent renewの挙動は持ち込まない。
  automaticSilentRenew: false,
  userStore: new WebStorageStateStore({ store: window.sessionStorage }),
};

export const userManager = new UserManager(settings);

// ----------------------------------------------------------------------------
// [設計メモ: 最優先要件に直結する唯一の既知の差異]
//
// oidc-dev-server(開発時、Cognito Hosted UI相当)は標準の
// RP-Initiated Logout(id_token_hint + post_logout_redirect_uri)を実装して
// いるため signoutRedirect() をそのまま呼べば良い。
//
// しかしCognito本番の /logout はこの標準に従わず、
// client_id / logout_uri という独自パラメータを要求する
// (これはCognito自体の仕様であり、本アプリ側の実装不備ではない)。
//
// この差異を吸収するため、呼び出し側(App.tsx)は必ずこの logout() 関数
// 経由でのみログアウトを行う設計にしている。Cognito移行時は、この関数の
// 中身だけを差し替えれば良く、App.tsx(呼び出し側)は無改修で済む。
// ----------------------------------------------------------------------------

export async function logout(): Promise<void> {
  const user = await userManager.getUser();

  // --- 現在: oidc-dev-server向け標準 RP-Initiated Logout ---
  await userManager.signoutRedirect({ id_token_hint: user?.id_token });

  // --- Cognito移行時はここを以下のような実装に差し替える(参考実装) ---
  // const cognitoDomain = import.meta.env.VITE_COGNITO_DOMAIN;
  // const url = new URL(`https://${cognitoDomain}/logout`);
  // url.searchParams.set("client_id", import.meta.env.VITE_OIDC_CLIENT_ID);
  // url.searchParams.set("logout_uri", import.meta.env.VITE_OIDC_POST_LOGOUT_REDIRECT_URI);
  // await userManager.removeUser();
  // window.location.href = url.toString();
}
