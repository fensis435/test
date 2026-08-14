# oidc-web-test

`oidc-dev-server`(Cognito Hosted UI相当)から始まる認証チェーンを、
バックエンドでのトークン検証まで含めて一気通貫で確認するための
最小構成テストアプリです。

以前のバージョン(Ruby/Sinatra単体クライアント)は、実際のターゲット
スタック(React + Vite + Rails v8)を反映していなかったため、本バージョン
で置き換えました。

## 全体構成

```
ブラウザ
  │
  ▼
React (Vite, :5173) ── oidc-client-ts ──┐
  │                                      │
  │ Authorization Code + PKCE            │
  ▼                                      ▼
oidc-dev-server (:3000)          Rails v8 API (:3001)
  Cognito Hosted UI相当              TokenVerifier
  (/authorize, /token,               (JWKS経由でAccess Token検証)
   /jwks.json 等)
```

Reactのトップページは、ログイン成功後に**Rails APIを実際に呼び出し、
その場でAccess Tokenの検証結果を表示する**ボタンを持ちます。この呼び出しが
成功して初めて、「ブラウザで発行されたトークンがバックエンドで正しく
検証できる」という一連の鎖全体が確認できたことになります。

```
oidc-web-test/
├── frontend/       # React + Vite (トップページのみ)
├── backend/        # Rails v8 API (TokenVerifierのみ)
├── scripts/
│   └── register_client.rb   # Reactクライアントの自動登録
└── README.md        (このファイル)
```

## 起動手順

### 0. 前提: oidc-dev-server が起動していること

```bash
cd path/to/oidc-dev-server
npm run dev
```

管理者アカウントも作成しておく:

```bash
SEED_ADMIN_EMAIL=admin@example.com SEED_ADMIN_PASSWORD=change-me-please npx prisma db seed
```

### 1. React用Clientの登録

```bash
cd oidc-web-test
ruby scripts/register_client.rb \
  --issuer http://localhost:3000 \
  --admin-email admin@example.com \
  --admin-password change-me-please
```

`--redirect-uri` / `--post-logout-redirect-uri` を省略した場合は
`http://localhost:5173/callback` / `http://localhost:5173/` が使われる。
独自ドメイン等に変更する場合は両方を明示的に指定すること
(`--redirect-uri` だけ変えても `postLogoutRedirectUris` は追従しない)。

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback \
  --post-logout-redirect-uri https://app.dev.test/
```

同じ`client_id`が既に登録済みの場合(2回目以降の実行、localhost↔独自ドメイン
間の切替時など)は`409`となり何も更新されない。`redirectUris`等を
更新したい場合は`--update`を付けて再実行する。

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback \
  --post-logout-redirect-uri https://app.dev.test/ \
  --update
```

### 2. Rails v8 API の起動

```bash
cd backend
bundle install
cp .env.example .env
bin/rails server
```

`http://localhost:3001/up` にアクセスして200が返ればOK。

### 3. React(Vite) の起動

```bash
cd frontend
npm install
cp .env.example .env
npm run dev
```

`http://localhost:5173` を開く。

## 確認手順

1. 「ログイン」ボタンを押す → oidc-dev-serverのログイン画面へリダイレクト
2. ログイン成功 → `/callback` 経由でトップページに戻り、ID Token claimsが表示される
3. 「Rails APIを呼ぶ」ボタンを押す → Rails側がAccess TokenをJWKS経由で検証し、
   結果(`verified: true` とクレーム)が画面に表示される
4. 「ログアウト」ボタンを押す → oidc-dev-serverのRP-Initiated Logoutを経由してセッションが破棄される

3番が成功すれば、Cognito Hosted UI相当のIdP → React → Railsという
認証チェーン全体が繋がっていることの確認は完了です。

## 検証済み事項(本回答作成時点)

- **frontend**: `npm install` → `npm run build`(`tsc -b && vite build`)まで実行し、型エラー・ビルドエラーがないことを確認済み
- **backend**: 全Rubyファイルの構文チェック(`ruby -c`)は実施済み。ただし`rubygems.org`への接続が制限された検証環境のため、`bundle install`によるRails自体の起動確認は**未実施**です。お手元の環境で`bin/rails server`実行時に問題が出た場合は、エラーメッセージを共有してください。

## Cognito移行時に変更が必要な箇所

| 箇所 | 変更内容 |
|---|---|
| `frontend/.env`(ローカル開発時のみ)または Helm values の `OIDC_ISSUER` | Cognito User PoolのURLに変更 |
| `frontend/src/auth.ts` の `logout()` 関数の中身 | Cognito独自のLogout URL形式に差し替え(コメントに参考実装あり) |
| `backend/.env` の `OIDC_ISSUER` | Cognito User PoolのURLに変更 |

上記以外(React側のコンポーネント、Rails側のTokenVerifier/Controller)は無改修で動作する設計です。

## [追加] ランタイム設定注入(Helm/K8s向け)

`frontend/src/runtime-config.ts` により、`import.meta.env.VITE_*`
(ビルド時にJSへハードコードされる)への依存を排除し、
`window.__APP_CONFIG__`(コンテナ起動時に`docker/generate-config.sh`が
動的生成する`config.js`経由)からランタイムで値を読む方式にしてある。

これにより **1回ビルドしたDockerイメージを、Helmの環境ごとのvaluesファイル
だけでdev/staging/本番すべてに使い回せる**(コンテナ再ビルド不要)。
サンプルは `frontend/docker/generate-config.sh` と
`frontend/docker/values-example.yaml` を参照。

ローカルで`npm run dev`(Vite dev server)を使う場合は、`window.__APP_CONFIG__`
が存在しないため`import.meta.env.VITE_*`へのフォールバックが効く
(`runtime-config.ts`参照)。`vite dev`を使わずビルド済みアセットのみを
使う開発フローの場合は、ローカルでも`docker/generate-config.sh`相当の
仕組みで`public/config.js`を生成しておくこと。

