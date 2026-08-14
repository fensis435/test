# ローカルHTTPS開発環境の構築(独自ドメイン + 自己証明書)

`localhost` でのHTTP開発から、自己署名証明書によるHTTPS + ローカルDNS独自ドメイン
での開発に移行する手順と、その際にCognito本番環境との差異がどう変化するかをまとめる。

## 0. なぜHTTPS化が必須なのか(単なる「望ましい」ではない)

ブラウザは `crypto.subtle`(Web Crypto API)を **secure context でしか使えない**。
secure contextと認められるのは `https://` のオリジンと、特別扱いされている
`http://localhost` だけ。

`oidc-client-ts` はPKCEの `code_challenge` 生成(SHA-256)に内部で
`crypto.subtle.digest` を使っている。そのため `http://app.dev.test` のような
独自ドメインに `localhost` のまま乗り換えると、**PKCE生成自体が失敗し
ログインボタンを押した瞬間に例外になる**。これは選択の問題ではなく動作要件。

## 1. 構成方針

3つのアプリ(oidc-dev-server / React・Vite / Rails)それぞれに個別にTLSを
持たせるのではなく、**リバースプロキシ1枚を手前に置き、各アプリは今まで通り
plain HTTPのままにする**。

- 各アプリのコード変更がほぼゼロで済む(環境変数のみで完結)
- 本番(EKS + ALB/Ingressがtlsを終端し、Pod自体はHTTPで待ち受ける)と
  構成が一致する。K8sマニフェストで作ってきた設計とそのまま地続きになる

```
ブラウザ
  │ https://
  ▼
リバースプロキシ (Caddy/nginx, TLS終端)
  │ http:// (X-Forwarded-Proto: https を付与)
  ├─→ oidc-dev-server (localhost:3000)
  ├─→ React/Vite       (localhost:5173)
  └─→ Rails v8 API      (localhost:3001)
```

## 2. セットアップ手順

### ① ドメインとhostsの決定

IANAが予約している `.test` を使う(実在ドメインと衝突しない)。

```
# /etc/hosts
127.0.0.1  idp.dev.test    # oidc-dev-server
127.0.0.1  app.dev.test    # React (Vite)
127.0.0.1  api.dev.test    # Rails v8 API
```

### ② mkcertで信頼済み証明書を発行

```bash
brew install mkcert   # または apt / choco 等
mkcert -install       # ローカルCAをOS/ブラウザの信頼ストアに登録(1回だけ)
mkcert idp.dev.test app.dev.test api.dev.test
# → idp.dev.test+2.pem / idp.dev.test+2-key.pem が生成される
```

### ③ Caddyでリバースプロキシ

```
# Caddyfile
idp.dev.test {
  tls idp.dev.test+2.pem idp.dev.test+2-key.pem
  reverse_proxy localhost:3000
}
app.dev.test {
  tls idp.dev.test+2.pem idp.dev.test+2-key.pem
  reverse_proxy localhost:5173
}
api.dev.test {
  tls idp.dev.test+2.pem idp.dev.test+2-key.pem
  reverse_proxy localhost:3001
}
```

```bash
caddy run
```

Caddyは `reverse_proxy` 使用時に `X-Forwarded-Proto` 等を自動付与するため、
この点で追加設定は不要(nginxの場合は `proxy_set_header X-Forwarded-Proto $scheme;`
等を明示的に書く必要がある)。

### ④ 各アプリの環境変数を変更(コード変更なし)

| アプリ | 変数 | 変更後の値 |
|---|---|---|
| oidc-dev-server | `OIDC_ISSUER` | `https://idp.dev.test` |
| oidc-dev-server | `OIDC_TRUST_PROXY` | `true`(**必須**、詳細は3節) |
| React | `VITE_OIDC_ISSUER` | `https://idp.dev.test` |
| React | `VITE_OIDC_REDIRECT_URI` | `https://app.dev.test/callback` |
| React | `VITE_OIDC_POST_LOGOUT_REDIRECT_URI` | `https://app.dev.test/` |
| React | `VITE_RAILS_API_BASE_URL` | `https://api.dev.test` |
| Rails | `OIDC_ISSUER` | `https://idp.dev.test` |
| Rails | `FRONTEND_ORIGIN` | `https://app.dev.test` |

### ⑤ Clientの再登録(必須)

`clientBasedCORS`(`src/oidc-core/provider.ts`)は**登録済みClientの
`redirectUris` からオリジンを動的に算出する**設計にしてある。そのため
`redirectUris` を新ドメインで登録し直せば、**CORS設定はコード変更なしで
自動的に追従する**。

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback
```

`register_client.rb` 内部の `Net::HTTP` はOS/mkcertのCAを通常通り信頼するため、
Ruby側での追加対応は不要。

## 3. `OIDC_TRUST_PROXY` が必要な理由

`src/infra/http/app.ts` の `app.set("trust proxy", 1)` はExpress自体の
プロキシ信頼設定であり、**oidc-provider自身には伝播しない**。oidc-provider
はKoaベースの独立したアプリケーションを内包しており、Expressとは別に
`proxy: true` を明示的に渡す必要がある(`src/oidc-core/provider.ts` に反映済み)。

これが無いと:
- Cookieの `Secure` 属性が付与されない(HTTPSなのにhttp扱いされる)
- `ctx.secure` / protocol判定がリバースプロキシの `X-Forwarded-Proto`
  ヘッダを見てくれず、内部的に「http」だと誤認する

`.env` の `OIDC_TRUST_PROXY=true` を設定すること。ローカルで
`http://localhost:3000` に直接アクセスする従来の開発フローに戻す場合は
`false`(既定値)のままでよい。

## 4. ViteのHMR(Hot Module Replacement)について

**運用がビルド済みアセットの配信のみ(`vite dev`のHMRサーバーを起動しない)
の場合、この節は不要。** リバースプロキシ設定も単純なリバースプロキシで
完結する(WebSocketの考慮が不要になる分、構成がシンプルになる)。

```
# Caddyfile (HMR不使用の場合。Railsが静的アセットも含めて配信する)
app.dev.test {
  tls idp.dev.test+2.pem idp.dev.test+2-key.pem
  reverse_proxy localhost:3001    # Rails(Vite統合)がアセットも含めて配信
}
```

もし将来 `vite dev` のHMRサーバーを併用する運用に切り替える場合は、
`frontend/vite.config.ts` に以下を追加する必要がある(HMR用WebSocketの
接続先がリバースプロキシ経由で食い違うのを防ぐため)。

```ts
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    hmr: {
      host: "app.dev.test",
      protocol: "wss",
    },
  },
});
```

## 5. 将来のための注意: Node.jsは自前のCAストアを持つ

現状の3アプリ構成では発生しないが、**もし `oidc-dev-server` 自身が別の
HTTPSサービス(独自ドメインのWebhook宛先など)にoutboundで接続する場合**、
Node.jsはOSの信頼ストアを見ず自前のバンドルCAリストしか信頼しない。
mkcertのCAを追加で信頼させるには、Node.jsプロセスに以下の環境変数を渡す。

```bash
export NODE_EXTRA_CA_CERTS="$(mkcert -CAROOT)/rootCA.pem"
```

Ruby(Rails / `oidc-ruby-test-client`)はOSの信頼ストアに乗るため、この対応は
基本的に不要。

## 6. Cognito本番環境との差異(このHTTPS化でどう縮まるか)

詳細は `PRODUCTION_PARITY.md` を参照。要点のみ:

このHTTPS化によって、Cookie/HTTPS/オリジン分離まわりの差異は**ほぼ解消**される。
`OIDC_TRUST_PROXY` を含むこの構成が、実質的に本番のALB Ingress配下での動作と
同一の前提条件(TLS終端はプロキシ側、アプリはHTTPで待受、`X-Forwarded-Proto`
経由でprotocol判定)を再現しているため。

残る既知の差異は、これまでのADRで整理してきた通り以下の2点に限定される。

1. Logout(Cognitoの非標準パラメータ) — `frontend/src/auth.ts` の `logout()`
   関数内に限定済み
2. Management API / Webhook(Cognito本番には存在しない領域) — Rails側の
   Port実装の差し替えのみで完結する設計
