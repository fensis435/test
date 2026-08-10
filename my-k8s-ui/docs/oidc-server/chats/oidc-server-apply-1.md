実は「`localhost`から独自ドメインに変える」というのは見た目以上に本質的な変更で、**HTTPS化は「望ましい」ではなく「必須」になります**。まずそこから説明し、その後の2点について整理します。

---

## 0. 前提:なぜHTTPS化が「必須」なのか

ブラウザは`crypto.subtle`(Web Crypto API)を**secure context(安全なコンテキスト)でしか使えません**。secure contextと認められるのは`https://`のオリジンと、特別扱いされている`http://localhost`だけです。

`oidc-client-ts`はPKCEの`code_challenge`生成(SHA-256)に内部で`crypto.subtle.digest`を使っています。つまり`http://app.dev.test`のような独自ドメインに`localhost`のまま乗り換えると、**PKCE生成自体が失敗してログインボタンを押した瞬間に例外になります**。これは「本番に寄せたいから」という選択の話ではなく、動作要件です。

---

## 1. ローカル開発環境でのoidc-serverの設置方法

### 構成方針

3つのアプリ(`oidc-dev-server`, React/Vite, Rails)それぞれに個別にTLSを持たせるより、**リバースプロキシ1枚を手前に置いて、各アプリは今まで通りplain HTTPのままにする**のがおすすめです。理由は2つあります。

- 各アプリのコード変更がほぼゼロで済む(`OIDC_ISSUER`等の環境変数だけで完結)
- 本番(EKS + ALB/Ingressがtlsを終端し、Pod自体はHTTPで待ち受ける)と構成が一致する — これまでK8s Ingressで作ってきた設計とそのまま地続きになります

### 手順

**① ドメインとhostsの決定**

IANAが予約している`.test`を使うのが無難です(実在ドメインと衝突しない)。

```
# /etc/hosts
127.0.0.1  idp.dev.test    # oidc-dev-server
127.0.0.1  app.dev.test    # React (Vite)
127.0.0.1  api.dev.test    # Rails v8 API
```

**② mkcertで信頼済み証明書を発行**

自己署名証明書をOSやブラウザに手動で信頼させる作業を`mkcert`が自動化してくれます。

```bash
brew install mkcert   # またはaptなど
mkcert -install       # ローカルCAをOS/ブラウザの信頼ストアに登録(1回だけ)
mkcert idp.dev.test app.dev.test api.dev.test
# → idp.dev.test+2.pem / idp.dev.test+2-key.pem が生成される
```

**③ Caddyでリバースプロキシ**

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

Caddyは`reverse_proxy`使用時に`X-Forwarded-Proto`等を自動付与するので、この点で追加設定は不要です。nginxでも同等のことができますが、Caddyの方が設定量が少なく事故りにくいです。

**④ 各アプリはこれまで通りplain HTTPでlisten**

`oidc-dev-server`は`PORT=3000`のまま、Railsは`3001`、Viteは`5173`のまま起動します。コード変更は不要です。

---

## 2. web-client側(React+Vite / Rails8)の移植時のポイント

### 環境変数の変更(コード変更なし)

| アプリ | 変数 | 変更後の値 |
|---|---|---|
| `oidc-dev-server` | `OIDC_ISSUER` | `https://idp.dev.test` |
| React | `VITE_OIDC_ISSUER` | `https://idp.dev.test` |
| React | `VITE_OIDC_REDIRECT_URI` | `https://app.dev.test/callback` |
| React | `VITE_OIDC_POST_LOGOUT_REDIRECT_URI` | `https://app.dev.test/` |
| React | `VITE_RAILS_API_BASE_URL` | `https://api.dev.test` |
| Rails | `OIDC_ISSUER` | `https://idp.dev.test` |
| Rails | `FRONTEND_ORIGIN` | `https://app.dev.test` |

### 【必須】Clientの再登録

`clientBasedCORS`は**登録済みClientの`redirectUris`からオリジンを動的に算出**する設計にしてあります(前回までの設計判断がここで効いてきます)。つまり`redirectUris`を`https://app.dev.test/callback`で登録し直せば、**CORS設定はコード変更なしで自動的に追従**します。

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback
```

※ `register_client.rb`内部の`Net::HTTP`はOS/mkcertのCAを普通に信頼するので、Ruby側での追加対応は基本的に不要です。

### 【要対応】`oidc-provider`に`proxy: true`の追加が必要

これが一番見落としやすい点です。`oidc-provider`は自前でKoaアプリを内包しており、Expressの`app.set("trust proxy", 1)`(既に設定済み)とは**別に、oidc-provider自身にもリバースプロキシ配下であることを教える必要があります**。

```ts
// provider.ts の Provider コンストラクタ引数に追加
const provider = new Provider(env.OIDC_ISSUER, {
  proxy: true,  // ← これが無いと ctx.secure が正しく判定されず、
                //    Cookieの Secure 属性やprotocol判定がおかしくなる
  // ...
});
```

これがないと、Caddy越しに`https`でアクセスしていてもoidc-provider内部では「httpだ」と誤認し、Cookieの`Secure`属性が付与されない、あるいはissuerとprotocolの不整合でエラーになる可能性があります。ご希望であれば、この修正は今すぐ実装できます。

### 【要注意】ViteのHMR(Hot Module Replacement)

Viteの開発サーバーはHMR用にWebSocketを内部で張りますが、リバースプロキシ経由だと接続先が食い違って壊れることがあります。`vite.config.ts`に以下を足すと安定します。

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

### 【将来のための注意】Node.jsは自前のCAストアを持つ

現状の3アプリ構成では発生しませんが、**もし`oidc-dev-server`自身が別のHTTPSサービス(独自ドメインのWebhook宛先など)にoutboundで接続する場合**、Node.jsはOSの信頼ストアを見ずに自前のバンドルCAリストしか信頼しません。mkcertのCAを追加で信頼させるには、

```bash
export NODE_EXTRA_CA_CERTS="$(mkcert -CAROOT)/rootCA.pem"
```

をNode.jsプロセスの環境変数に設定する必要があります。Ruby(Rails/`oidc-ruby-test-client`)はOSの信頼ストアに乗るのでこの対応は基本的に不要です。
