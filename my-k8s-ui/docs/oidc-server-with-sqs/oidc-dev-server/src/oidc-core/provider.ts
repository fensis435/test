import { readFileSync } from "node:fs";
import Provider, { errors as OidcErrors } from "oidc-provider";
import { env } from "../config/env.js";
import { PrismaOidcAdapter } from "./adapter.js";
import { claimsConfig, scopesSupported, findAccount, extraAccessTokenClaims } from "./claims.js";

// ----------------------------------------------------------------------------
// oidc-provider 設定方針(前回設計のoidc-provider設定方針節を忠実に反映)
//
//   - features.devInteractions: 無効化(独自ログイン画面を使用)
//   - features.revocation: 有効化(RFC 7009)
//   - features.introspection: 有効化(RFC 7662)
//     [修正: レビュー指摘#3] Access TokenをJWT化するため必須ではないが、
//     Confidential Client(Rails BFF等)がAccess Tokenの失効状態を
//     JWKS検証だけでは判定できない(失効済みでもJWT自体は有効に見える)
//     ため、多層防御として有効化する。
//   - features.rpInitiatedLogout: 有効化(標準Logout。Cognitoとの差異は
//     Reactラッパー側で吸収する設計のため、ここは標準のまま)
//   - PKCE: 全クライアントで必須
//   - Cognito固有のクレーム名・スコープ・パラメータは一切定義しない
//
// [修正: レビュー指摘#3 → 再修正]
//   当初 `formats: { AccessToken: "jwt" }` という設定でAccess TokenのJWT化を
//   試みたが、これはoidc-provider v8には存在しない設定キーであり
//   (黙って無視され、Access Tokenはopaqueのままだった)、実機テストで
//   Rails側のJWT検証が"Not enough or too many segments"エラーになって
//   初めて発覚した。
//
//   oidc-provider v8でAccess TokenをJWT化する正しい方法は
//   features.resourceIndicators 経由でリソースサーバーを定義し、
//   そのリソースサーバーの accessTokenFormat を 'jwt' に設定すること。
//   本来「複数API・複数audience」を扱うための機能だが、このシステムには
//   Rails API という単一のリソースしかないため、defaultResource /
//   useGrantedResource を使い、Reactが resource パラメータを一切
//   意識しなくても(/authorize, /token どちらでも省略可能)常にこの
//   単一リソース向けのJWT Access Tokenが発行されるようにしている
//   (最優先要件である「Reactのコード変更を伴わない」ことを維持するため)。
//
// [修正: レビュー指摘#4] clientBasedCORS を追加。
//   React(Vite: 別オリジン)からのブラウザfetchが/token・/userinfoに対して
//   CORSでブロックされていた問題に対応。登録済みClientのredirectUrisの
//   オリジンをそのまま許可オリジンとして扱う(Client登録と一致させることで
//   個別のCORS許可リスト管理を不要にする設計)。
// ----------------------------------------------------------------------------

// このシステムが持つ唯一のリソースサーバー(Rails API)を表す固定の識別子。
// 複数リソースサーバーを持つ本格的なマイクロサービス構成になった場合は、
// defaultResource/getResourceServerInfo をクライアント/スコープに応じて
// 動的に切り替える設計に拡張すること。
const RAILS_API_RESOURCE_INDICATOR = `${env.OIDC_ISSUER}/resources/rails-api`;

function loadJwks(): { keys: unknown[] } {
  const raw = readFileSync(env.OIDC_JWKS_PATH, "utf-8");
  return JSON.parse(raw) as { keys: unknown[] };
}

function originFromUri(uri: string): string | null {
  try {
    return new URL(uri).origin;
  } catch {
    return null;
  }
}

export function createOidcProvider(): Provider {
  const jwks = loadJwks();

  const provider = new Provider(env.OIDC_ISSUER, {
    adapter: PrismaOidcAdapter,
    jwks,

    findAccount,

    claims: claimsConfig,
    scopes: [...scopesSupported],

    cookies: {
      keys: env.OIDC_COOKIE_KEYS_ARRAY,
      long: { signed: true, sameSite: "lax" },
      short: { signed: true, sameSite: "lax" },
    },

    features: {
      devInteractions: { enabled: false },
      revocation: { enabled: true },
      introspection: { enabled: true },
      rpInitiatedLogout: { enabled: true },
      userinfo: { enabled: true },

      // [修正] Access TokenのJWT化には resourceIndicators が必須
      // (詳細は上部コメント参照)。Reactは resource パラメータを一切
      // 送らない前提のため、defaultResource / useGrantedResource で
      // 常に単一リソース(Rails API)が自動的に使われるようにする。
      resourceIndicators: {
        enabled: true,

        // /authorize 時に resource パラメータが省略された場合の既定値。
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        defaultResource: async (_ctx: any) => RAILS_API_RESOURCE_INDICATOR,

        // /token 時に resource パラメータが省略されても、既に付与済みの
        // リソースをそのまま使ってよいことにする(Reactに実装変更を
        // 求めないための設定)。
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        useGrantedResource: async (_ctx: any) => true,

        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        getResourceServerInfo: async (_ctx: any, resourceIndicator: string) => {
          if (resourceIndicator !== RAILS_API_RESOURCE_INDICATOR) {
            // 未知のresourceが明示的に要求された場合は拒否する
            // (登録していないAPIへのAccess Token発行を防ぐ)。
            throw new OidcErrors.InvalidTarget("unknown resource indicator");
          }

          return {
            scope: [...scopesSupported].join(" "),
            accessTokenFormat: "jwt",
            jwt: { sign: { alg: "RS256" } },
          };
        },
      },
    },

    pkce: {
      required: () => true,
      methods: ["S256"],
    },

    responseTypes: ["code"],

    tokenEndpointAuthMethods: ["none", "client_secret_basic"],

    ttl: {
      AuthorizationCode: 60, // 秒。短命。
      AccessToken: 3600, // 1時間。Cognitoデフォルト相当。
      IdToken: 3600,
      RefreshToken: 2592000, // 30日。Cognitoデフォルト相当。
      Session: 1209600, // 14日。
      Interaction: 3600,
      Grant: 2592000,
    },

    // [注記] oidc-provider の configuration オブジェクトは
    // Record<string, unknown> としてしか型付けできない(src/types/oidc-provider.d.ts
    // 参照)ため、以下の各コールバックの引数はコンテキスト型推論が効かない。
    // 正直に `any` として明示する(実際の形はoidc-providerのドキュメントに
    // 依拠しており、型システムでは保証できないことを隠さないため)。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    extraTokenClaims: async (_ctx: any, token: any) => {
      if (token.kind === "AccessToken") {
        return extraAccessTokenClaims();
      }
      return {};
    },

    interactions: {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      url: (_ctx: any, interaction: any) => `/interaction/${interaction.uid}`,
    },

    routes: {
      authorization: "/authorize",
      token: "/token",
      userinfo: "/userinfo",
      jwks: "/jwks.json",
      revocation: "/revoke",
      introspection: "/introspect",
      end_session: "/logout",
    },

    // [修正: レビュー指摘#4]
    // 登録済みClientのredirectUris/postLogoutRedirectUrisのオリジンのみを許可する。
    // 未登録オリジンからのCORSは拒否することで、Client登録台帳がそのまま
    // CORS許可リストとしても機能する(二重管理を避ける設計)。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    clientBasedCORS: (_ctx: any, origin: string, client: any) => {
      const allowedOrigins = new Set<string>();
      for (const uri of client.redirectUris ?? []) {
        const o = originFromUri(uri);
        if (o) allowedOrigins.add(o);
      }
      for (const uri of client.postLogoutRedirectUris ?? []) {
        const o = originFromUri(uri);
        if (o) allowedOrigins.add(o);
      }
      return allowedOrigins.has(origin);
    },

    // [修正] oidc-provider起動時のNOTICE
    // ("default renderError function called, you SHOULD change it")に対応。
    // デフォルトのエラー画面は詳細を一切表示しないため、原因調査に
    // 非常に時間がかかっていた。開発環境では実際のエラー内容を画面にも
    // 出すことで、以後のデバッグを大幅に短縮する。
    // 本番相当環境で使う場合は、ここをスタックトレース非表示の
    // ユーザー向け文言に差し替えること。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    renderError: async (ctx: any, out: any, error: any) => {
      // eslint-disable-next-line no-console
      console.error("[oidc-provider] renderError:", error);
      ctx.type = "html";
      ctx.body = `<!DOCTYPE html>
<html lang="ja">
<head><meta charset="utf-8"><title>OIDC Error</title></head>
<body>
  <h1>oidc-provider error</h1>
  <pre>${escapeHtml(JSON.stringify(out, null, 2))}</pre>
  <p style="color:#888;font-size:0.85rem;">
    開発環境向けの詳細表示です。本番相当環境ではこの内容を表示しないよう
    src/oidc-core/provider.ts の renderError を差し替えてください。
  </p>
</body>
</html>`;
    },
  });

  // [修正] proxy はコンストラクタの configuration オプションではなく、
  // Provider インスタンスの getter/setter プロパティとして公開されている
  // (node_modules/oidc-provider/lib/provider.js の `get proxy()` /
  // `set proxy()` 参照。内部的には Koa アプリの `app.proxy` に代入される)。
  // 以前 `new Provider(issuer, { proxy: true, ... })` のように渡していたが、
  // これは configuration オブジェクトの未知のキーとして黙って無視されて
  // おり、`ctx.secure` が常にfalseのままだった
  // (`x-forwarded-proto header detected but not trusted` WARNINGの原因)。
  // これは以前の `formats: { AccessToken: "jwt" }` の誤りと全く同じ
  // 「存在しない設定キーを渡して黙って無視される」パターンである。
  provider.proxy = env.OIDC_TRUST_PROXY;

  // renderErrorだけでは拾えない、5xx相当のサーバー内部エラーの詳細
  // (スタックトレース含む)をログに出す。renderErrorのoutにはエラーの
  // 概要しか含まれないため、実際のデバッグにはこちらのログが必要になる。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  provider.on("server_error", (_ctx: any, err: any) => {
    // eslint-disable-next-line no-console
    console.error("[oidc-provider] server_error:", err);
  });

  return provider;
}

function escapeHtml(value: string): string {
  return value.replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string
  );
}
