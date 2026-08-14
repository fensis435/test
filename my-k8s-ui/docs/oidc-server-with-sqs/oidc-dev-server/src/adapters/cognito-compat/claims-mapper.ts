// ----------------------------------------------------------------------------
// Cognito Compat Adapter
//
// このファイルは本OIDC開発サーバー内では実行時に使用されない
// (このサーバー自体は常に中立的な標準クレーム名 `groups` を出力する)。
//
// 目的は、将来Cognitoへ切り替えた際に「Rails側で実装すべき変換ロジックの
// リファレンス実装」をここに集約し、Cognito固有仕様への依存箇所を
// このファイル1つに限定することである。
//
// 実際の切替時、Rails側の IdentityManagementPort / TokenVerifierPort の
// Cognito実装はこのファイルと同等のマッピングを行う。
//
// Cognito固有知識(このファイル以外に絶対に漏らしてはならない):
//   - グループ情報は `cognito:groups` というプレフィックス付きクレームで
//     提供される
//   - `cognito:username` は本サーバーの `sub` とは異なる場合がある
//   - Access TokenにはPIIクレームが含まれない
//   - RP-Initiated Logoutは非標準(client_id / logout_uri を使用)
// ----------------------------------------------------------------------------

export interface NeutralClaims {
  sub: string;
  email?: string;
  email_verified?: boolean;
  given_name?: string | null;
  family_name?: string | null;
  groups?: string[];
}

export interface CognitoStyleClaims {
  sub: string;
  email?: string;
  email_verified?: boolean;
  given_name?: string | null;
  family_name?: string | null;
  "cognito:groups"?: string[];
  "cognito:username"?: string;
  token_use?: "id" | "access";
}

/**
 * Cognitoから返却された生クレームを、本サーバーが定義した中立クレーム契約
 * (Claims設計)に正規化する。Railsはこの関数相当のロジックを経由してのみ
 * クレームを参照することで、IdP実装に依存しないコードを維持できる。
 */
export function normalizeCognitoClaims(cognitoClaims: CognitoStyleClaims): NeutralClaims {
  return {
    sub: cognitoClaims.sub,
    email: cognitoClaims.email,
    email_verified: cognitoClaims.email_verified,
    given_name: cognitoClaims.given_name ?? null,
    family_name: cognitoClaims.family_name ?? null,
    groups: cognitoClaims["cognito:groups"] ?? [],
  };
}

/**
 * 開発OIDCサーバーが返す中立クレームを、Cognito互換形式へ変換する
 * (統合テストで本番相当の形式を模擬したい場合にのみ使用するユーティリティ)。
 */
export function toCognitoStyleClaims(neutral: NeutralClaims): CognitoStyleClaims {
  return {
    sub: neutral.sub,
    email: neutral.email,
    email_verified: neutral.email_verified,
    given_name: neutral.given_name,
    family_name: neutral.family_name,
    "cognito:groups": neutral.groups ?? [],
    "cognito:username": neutral.sub,
  };
}

/**
 * Cognitoの非標準Logout URLを構築する(Reactラッパー実装のリファレンス)。
 * 標準RP-Initiated Logout(id_token_hint + post_logout_redirect_uri)とは
 * パラメータ形式が異なる点に注意。
 */
export function buildCognitoLogoutUrl(params: {
  cognitoDomain: string;
  clientId: string;
  logoutUri: string;
}): string {
  const url = new URL(`https://${params.cognitoDomain}/logout`);
  url.searchParams.set("client_id", params.clientId);
  url.searchParams.set("logout_uri", params.logoutUri);
  return url.toString();
}
