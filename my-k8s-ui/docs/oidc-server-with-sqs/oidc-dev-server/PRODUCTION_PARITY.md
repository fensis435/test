# Cognito(本番)との差異 一覧

このドキュメントは、`oidc-dev-server` から AWS Cognito Hosted UI への切替時に
生じる**既知の差異のすべて**を一箇所に集約したものである。設計判断がコード
コメントとチャット履歴に分散していた反省(3年後の保守性レビューで指摘済み)を
踏まえ、ADR(Architecture Decision Record)的にここへ集約する。

最優先要件は「React/Railsのコード変更を最小化すること」。以下は、その要件に
対する**現時点での例外(コード変更が必要な箇所)を漏れなく列挙したもの**であり、
新たな差異が見つかった場合は都度ここに追記すること。

---

## 差異1: RP-Initiated Logout(唯一の必須コード変更・React側)

### 差異の内容

標準OIDCのRP-Initiated Logoutは `id_token_hint` + `post_logout_redirect_uri`
を使う。`oidc-dev-server` はこの標準に準拠している。

一方、**Cognitoの `/logout` エンドポイントはこの標準に従わず**、
`client_id` + `logout_uri` という独自パラメータを要求する。これはCognito
自体の仕様であり、本プロジェクトの実装不備ではない。

### 影響範囲(最小化済み)

`frontend/src/auth.ts` の `logout()` 関数の中身のみ。呼び出し側
(`App.tsx` 等のコンポーネント)は無改修。

```ts
export async function logout(): Promise<void> {
  const user = await userManager.getUser();

  // --- 現在: oidc-dev-server向け標準 RP-Initiated Logout ---
  await userManager.signoutRedirect({ id_token_hint: user?.id_token });

  // --- Cognito移行時はここを以下のような実装に差し替える ---
  // const cognitoDomain = import.meta.env.VITE_COGNITO_DOMAIN;
  // const url = new URL(`https://${cognitoDomain}/logout`);
  // url.searchParams.set("client_id", import.meta.env.VITE_OIDC_CLIENT_ID);
  // url.searchParams.set("logout_uri", import.meta.env.VITE_OIDC_POST_LOGOUT_REDIRECT_URI);
  // await userManager.removeUser();
  // window.location.href = url.toString();
}
```

---

## 差異2: Management API / Webhook(Cognito本番には存在しない領域)

### 差異の内容

User CRUD、Password、Enable/Disable、Groups、Clients管理、Webhook配信、
管理者ログインという `oidc-dev-server` の `/api/v1/*` は、Cognito本番には
1:1で対応する仕組みが存在しない。Cognitoでの相当機能は以下のようにAWS側の
機構に置き換わる。

| oidc-dev-server | Cognito本番での相当機能 |
|---|---|
| User CRUD | AWS SDK `AdminCreateUser` 等(REST形状が根本的に異なる) |
| Password | `AdminSetUserPassword` 等 |
| Enable/Disable | `AdminEnableUser` / `AdminDisableUser` |
| Groups | `AdminAddUserToGroup` 等 |
| Webhook | Lambdaトリガー(PreSignUp/PostConfirmation等の同期呼び出し。
  HTTPSエンドポイント形式ではない) |
| 管理者ログイン(`/api/v1/auth/login`) | 対応物なし(IAM/Cognito管理コンソール等) |

### 影響範囲

RailsのIdentityManagementPort/UserLifecycleEventPortの実装を差し替えるのみ。
**Rails側もポート(インターフェース)自体は変更不要**、実装(アダプタ)のみの
差し替えで済む設計にしてある。Reactはこれらのエンドポイントに一切触れない
設計のため、影響なし。

---

## 差異3: クレーム名(`groups`)

### 差異の内容

`oidc-dev-server` はGroupsを中立名の `groups` クレームとして発行する。
Cognitoは `cognito:groups` というベンダープレフィックス付きクレームで
グループ情報を提供する。

### 影響範囲

`src/adapters/cognito-compat/claims-mapper.ts`(oidc-dev-server側)に
変換ロジックのリファレンス実装がある。Rails側でクレームを読み取る箇所
(`TokenVerifier` 等)が、この中立名 `groups` を経由してのみクレームに
アクセスする設計にしてあれば、Cognito移行時はRails側のTokenVerifier
実装(アダプタ層)でこの変換を行うだけでよい。

**要確認**: Rails側の実装(本番向けに実装する場合)で、認可ロジックが
`groups` という中立命名を前提にできているか。まだであれば早期に確定させる
ことを推奨(以前のレビューでも指摘済みの継続課題)。

---

## 差異4: Access Tokenの中身(意図的に最初から揃えてある差異ゼロ項目)

### 内容

Cognitoのデフォルト設定では、Access TokenにPII(email等)を含めない
(ID Tokenのみに含まれる)。`oidc-dev-server` も `extraTokenClaims` で
Access Tokenへの追加クレーム注入を意図的に行っておらず、この点は
**最初から差異がない**(本番切替時の変更不要)。

Access TokenがJWT形式である点も、`features.resourceIndicators` 経由で
JWT化しており、Cognito本番と形式が一致している(本番切替時の変更不要)。

---

## 差異5: HTTPS/リバースプロキシ関連(このドキュメントで新たに整理)

### 内容

ローカル開発を `http://localhost` から独自ドメイン + HTTPS
(`LOCAL_HTTPS_SETUP.md` 参照)に切り替えることで、本番のALB Ingress配下
での動作条件(TLS終端はプロキシ側、アプリ自体はHTTPで待受、
`X-Forwarded-Proto` 経由でのprotocol判定)とほぼ同一の条件を再現できる。

`OIDC_TRUST_PROXY=true` の設定と `provider.ts` の `proxy: true` が、
このパリティを支える実装。

### 影響範囲

コード変更なし(環境変数のみで両モードを切り替え可能)。

---

## 差異一覧サマリー

| # | 差異 | 影響範囲 | コード変更の要否 |
|---|---|---|---|
| 1 | RP-Initiated Logout | `frontend/src/auth.ts` の `logout()` | **要(唯一の必須変更)** |
| 2 | Management API / Webhook | Rails側Port実装(アダプタのみ) | 要(Rails実装側、Port自体は不変) |
| 3 | クレーム名(`groups`) | Rails側TokenVerifier(要確認) | 要確認・要対応の可能性 |
| 4 | Access Tokenの中身 | なし | 不要 |
| 5 | HTTPS/プロキシ | なし(環境変数のみ) | 不要 |

**このリストが「最優先要件(コード変更最小化)がどこまで達成できているか」の
唯一の正とする。** 新たな差異が判明した場合は、都度この表に追記すること。
