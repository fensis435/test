# セットアップ手順

初回セットアップで必要な手順をここに集約する。過去の指示で断片的にしか
案内していなかった箇所(.env作成、JWKS生成)を含む。

## 1. 依存関係のインストール

```bash
npm install
npx prisma generate
```

## 2. 環境変数ファイルの作成

`.env.example` は秘密情報を含まないテンプレートであり、これをコピーして
実際の値を設定した `.env` を作成する(`.env` はGit管理対象外)。

```bash
cp .env.example .env
```

`.env` の主要な値:

| 変数 | 説明 | ローカル開発時の例 |
|---|---|---|
| `DATABASE_URL` | SQLiteファイルパス | `file:./dev.db` |
| `OIDC_ISSUER` | Discoveryで公開するissuer URL | `http://localhost:3000` |
| `OIDC_COOKIE_KEYS` | Cookie署名鍵(カンマ区切りで複数可) | ランダムな長い文字列に変更すること |
| `OIDC_JWKS_PATH` | JWKS秘密鍵ファイルの場所 | `./secrets/jwks.json` |
| `ADMIN_JWT_SECRET` | 管理者トークン署名鍵 | ランダムな長い文字列に変更すること |

`OIDC_COOKIE_KEYS` / `ADMIN_JWT_SECRET` は以下のように生成できる:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

## 3. JWKS(署名鍵)の生成

`.env` で指定した `OIDC_JWKS_PATH` にJWKS秘密鍵ファイルが存在しないと、
サーバー起動時に読み込みエラーになる。以下のスクリプトで生成する。

```bash
npm run generate:jwks
```

既存ファイルを上書きしたい場合(鍵ローテーション等)は `-- --force` を付ける。

```bash
npm run generate:jwks -- --force
```

## 4. データベースのマイグレーション

```bash
npx prisma migrate dev --name init
```

## 5. 初期データの投入(任意)

React用Public Client、管理者アカウント等を投入する場合:

```bash
SEED_ADMIN_PASSWORD=change-me-please \
SEED_TEST_USER_PASSWORD=test-password-1234 \
npx prisma db seed
```

**重要**: `SEED_ADMIN_PASSWORD`で作られる**管理者アカウント(AdminUser)**と、
`SEED_TEST_USER_PASSWORD`で作られる**テスト用エンドユーザー(User)**は
完全に別物です。

| | 用途 | ログイン先 |
|---|---|---|
| `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD` | Management API(`/api/v1/*`)の操作専用 | `POST /api/v1/auth/login` |
| `SEED_TEST_USER_EMAIL` / `SEED_TEST_USER_PASSWORD` | ブラウザのOIDCログイン画面から実際にログインするアカウント | `/interaction/:uid/login`(Reactの「ログイン」ボタンから遷移する画面) |

管理者アカウントの認証情報でブラウザログイン画面からログインしようとすると
「認証に失敗しました。」と表示されます(意図通りの挙動です)。React側で
ログインを試す場合は、必ず`SEED_TEST_USER_*`で作成したアカウントを使ってください。

## 6. 起動

```bash
npm run dev
```

起動後、以下で疎通確認できる。

```bash
curl http://localhost:3000/.well-known/openid-configuration
```

## 6-2. Docker Composeでのビルド・初期化・起動(npm/Node.jsをホストに入れたくない場合)

手順2まで(`.env`作成)は同じ。JWKS生成・マイグレーション・シードは
`migrate`/`seed`と同じ「ワンショットコンテナ」パターンで実行する。

### ① イメージのビルド

```bash
docker compose build
```

### ② JWKS(署名鍵)の生成

```bash
docker compose --profile jwks run --rm jwks
```

`oidc-jwks` という名前付きボリュームに `jwks.json` が生成される
(`oidc-dev-server` サービス起動時と同じボリュームを共有するため、
一度生成すれば以後の`docker compose up`で使い回される)。

### ③ マイグレーション

```bash
docker compose --profile migrate run --rm migrate
```

### ④ シード(任意)

```bash
docker compose --profile seed run --rm seed
```

デフォルトでは`docker-compose.yml`内に`SEED_ADMIN_EMAIL=admin@example.com` /
`SEED_ADMIN_PASSWORD=change-me-please`がハードコードされている。変更したい
場合は`docker-compose.yml`の`seed`サービスの`environment`を書き換えるか、
以下のように上書きして実行する。

```bash
SEED_ADMIN_PASSWORD=my-password docker compose --profile seed run --rm \
  -e SEED_ADMIN_PASSWORD \
  -e SEED_TEST_USER_PASSWORD=test-password-1234 \
  seed
```

### ⑤ 起動

```bash
docker compose up -d oidc-dev-server
```

`http://localhost:3000/.well-known/openid-configuration` で疎通確認できる。

### ログの確認・停止

```bash
docker compose logs -f oidc-dev-server
docker compose down          # コンテナを止める(ボリュームは残る)
docker compose down -v       # ボリュームごと完全に削除する(DB/JWKSが消える)
```

### つまずきやすい点(Docker Compose特有)

| 症状 | 原因 | 対処 |
|---|---|---|
| `oidc-dev-server`起動時にJWKS読み込みエラー | 手順②(`--profile jwks run`)を実施していない | `docker compose --profile jwks run --rm jwks` を実行してから`up` |
| `EACCES: permission denied, open '/secrets/jwks/jwks.json'`(`jwks`/`migrate`/`seed`実行時、または起動時) | 2段階の原因があった。(1) 当初これらのサービスは`root`権限で実行され、生成ファイルが`root`所有になり、非root(`appuser`, uid 1001)の`oidc-dev-server`が読めなかった。(2) `user: "1001:1001"`を追加してプロセスをuid 1001にしても、**空の名前付きボリュームのマウントポイント自体をDockerがroot所有・mode 0755で新規作成する**ため、その中へのファイル作成自体が権限不足になった(`target: build`イメージには`/secrets/jwks`/`/data`が元々存在せず、所有権をruntimeイメージのように事前設定できないため) | 本リポジトリの最新版では解消済み。initコンテナの定石パターンに変更: `user:`指定を削除し(root実行に戻す)、`entrypoint: ["sh","-c"]` + `command`で本来の処理の後に`chown -R 1001:1001 <対象ディレクトリ>`を実行するようにした。rootはディレクトリの所有者が誰であっても書き込み・chownが可能なため、この順序であれば権限エラーが起きない。既に一度実行してしまっている場合は`docker compose down -v`でボリュームを削除してから①からやり直すこと |
| `oidc-dev-server`起動時にDB関連エラー | 手順③(マイグレーション)を実施していない | `docker compose --profile migrate run --rm migrate` を実行してから`up` |
| `.env`を変更したのに反映されない | `oidc-dev-server`サービスは`env_file: .env`を読むが、コンテナは再作成しないと反映されない | `docker compose up -d --force-recreate oidc-dev-server` |

## 7. ユーザー管理CLI(任意)

`scripts/manage_users.rb` で、User CRUD(ブラウザログイン用エンドユーザー)を
curlを都度打たずに操作できる。

```bash
export OIDC_ISSUER=https://idp.dev.test
export ADMIN_EMAIL=admin@example.com
export ADMIN_PASSWORD=change-me-please

ruby scripts/manage_users.rb list
ruby scripts/manage_users.rb list --status ACTIVE --all
ruby scripts/manage_users.rb create --email new@example.com --password correct-horse-battery
ruby scripts/manage_users.rb show <user_id>
ruby scripts/manage_users.rb update <user_id> --given-name 次郎
ruby scripts/manage_users.rb disable <user_id>
ruby scripts/manage_users.rb enable <user_id>
ruby scripts/manage_users.rb set-password <user_id> --password new-secure-password
ruby scripts/manage_users.rb add-group <user_id> <group_id>
ruby scripts/manage_users.rb remove-group <user_id> <group_id>
ruby scripts/manage_users.rb delete <user_id>
```

`--json` を付けると整形テーブルではなく生JSONで出力される(スクリプトからの
利用向け)。詳しいオプション一覧は `ruby scripts/manage_users.rb` (引数なし)
で表示される。

## つまずきやすいポイント

| 症状 | 原因 | 対処 |
|---|---|---|
| ログイン後に `invalid_grant` / `grant not found`(トークン交換時) | 過去バージョンの`schema.prisma`を使っている(`AuthorizationCode`に`grantId`カラムがなかった) | 本リポジトリの最新版では解消済み。既に`prisma migrate dev --name init`を実行済みの環境で更新する場合は、以下を実行してマイグレーションを追加すること:<br>`npx prisma migrate dev --name add_authorization_code_grant_id` |
| トークン交換時に `ERR_INVALID_ARG_TYPE`(`ctx.oidc.provider.AuthorizationCode`のconsume時) | `adapter.ts`の`find()`が`jti`を返却していなかった。oidc-providerはfind()で取得したpayloadから`this.jti`を復元してconsume()時に使うため、jtiが欠落しているとadapter.consume(undefined)が呼ばれクラッシュしていた | 本リポジトリの最新版では解消済み(`authorizationCodeStrategy`/`refreshTokenStrategy`の両方に`jti: id`を追加)。マイグレーション不要、コード更新のみで解消 |
| Rails APIが401、`"Not enough or too many segments"` | Access Tokenがopaque形式のまま発行されていた。原因は2段階: (1) 当初`formats: { AccessToken: "jwt" }`という存在しない設定キーを使っていた (2) `resourceIndicators`を正しく設定した後も、`adapter.ts`が`AuthorizationCode`/`RefreshToken`の`resource`フィールドを保存・返却しておらず、`/token`交換時に`resolveResource()`が`code.resource === undefined`と判定してしまい、JWT化のトリガー(`useGrantedResource`)にすら到達していなかった | 本リポジトリの最新版では解消済み。`prisma/schema.prisma`に`AuthorizationCode.resource`/`RefreshToken.resource`カラムを追加し、`adapter.ts`で正しく往復させるようにした。**マイグレーションが必要**:<br>`npx prisma migrate dev --name add_resource_indicator_fields` |
| リバースプロキシ配下(HTTPS独自ドメイン)で`x-forwarded-proto header detected but not trusted`のWARNINGが消えない。Discoveryドキュメントの各エンドポイントが`http://`のまま返る(issuerだけは`https://`) | `proxy`はoidc-providerの`new Provider(issuer, { proxy: true, ... })`という**コンストラクタのconfigurationオプションではなく**、`provider.proxy = true`という**インスタンス生成後に代入するgetter/setterプロパティ**だった。コンストラクタに渡していた`proxy: true`は未知のキーとして黙って無視されていた(`formats: { AccessToken: "jwt" }`の誤りと全く同じパターン) | 本リポジトリの最新版では解消済み。`provider.ts`で`new Provider(...)`実行後に`provider.proxy = env.OIDC_TRUST_PROXY;`を代入するよう修正。マイグレーション不要、コード更新のみで解消(`OIDC_TRUST_PROXY=true`の`.env`設定自体は変更不要) |

| 症状 | 原因 | 対処 |
|---|---|---|
| `Environment variable not found: DATABASE_URL`(`prisma migrate`実行時) | `.env` が存在しない、または読み込まれていない | 手順2を実施。カレントディレクトリが `oidc-dev-server` 直下であることを確認 |
| `Invalid environment variables: { ... Required ... }`(`npm run dev`実行時) | `.env`は存在するが、アプリ自体が読み込んでいない(dotenv未使用だった実装不備。現在は修正済み) | 最新版のリポジトリを使用していれば発生しない。発生する場合は`src/config/env.ts`の先頭に`loadDotenv()`呼び出しがあるか確認 |
| `npm run dev` 実行時に `SyntaxError: Unexpected string`(`node_modules/generator-function/require.mjs` 経由) | `oidc-provider → koa → is-generator-function → generator-function` という依存チェーンで、`generator-function@2.0.1` が使う「文字列をexport名に使う」構文(Arbitrary Module Namespace Names)を、tsx内部のesbuildがCJS変換する際に不正なコード(`0 && (module.exports = {"module.exports"})`)を生成してしまう既知のesbuildバグ。**アプリケーションコードの不具合ではない** | `package.json` の `overrides` で `is-generator-function` を `1.0.10`(`generator-function`に依存しない最終バージョン)に固定済み。`npm install` をやり直せば解消する。将来 `koa`/`is-generator-function`/`generator-function`/`esbuild` のいずれかが更新されて根本修正されたら、この`overrides`は削除してよい |
| `ENOENT` でJWKSファイルが読めない | 手順3を実施していない | `npm run generate:jwks` を実行 |
| `enum` 関連の `P1012` エラー | 過去バージョンのschema.prismaを使っている | 本リポジトリの最新版では解消済み(SQLiteはネイティブenum非対応のためString型に変更済み) |
| `prisma generate` がバイナリ取得で失敗する | 社内ネットワーク/プロキシ制限で `binaries.prisma.sh` に到達できない | ネットワーク許可設定を確認するか、`PRISMA_ENGINES_MIRROR` 等の代替ミラー設定を検討 |
