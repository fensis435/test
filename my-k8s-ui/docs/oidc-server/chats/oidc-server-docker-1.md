## 事前に見つけた抜け:JWKS生成ステップの欠落

説明の前に、既存の`docker-compose.yml`を確認したところ、**`oidc-dev-server`サービスは`/secrets/jwks/jwks.json`を必要とするのに、それを生成する仕組みがどこにも定義されていませんでした**。`migrate`/`seed`と同じ「プロファイル付きワンショットコンテナ」パターンで`jwks`サービスを追加し、`generate-jwks.ts`が位置引数でパス指定できる実装であることも確認済みです。

## 手順

### ① `.env`の準備

```bash
cp .env.example .env
# OIDC_ISSUER, OIDC_COOKIE_KEYS, ADMIN_JWT_SECRET等を編集
```

### ② イメージのビルド

```bash
docker compose build
```

### ③ JWKS(署名鍵)の生成【新規追加】

```bash
docker compose --profile jwks run --rm jwks
```

`oidc-jwks`という名前付きボリュームに`jwks.json`が書き込まれます。本体サービスとボリュームを共有しているので、一度だけ実行すれば以降は再利用されます。

### ④ マイグレーション

```bash
docker compose --profile migrate run --rm migrate
```

### ⑤ シード(任意、管理者アカウント/テストユーザー作成)

```bash
docker compose --profile seed run --rm seed
```

デフォルトの管理者アカウントを変えたい場合は`-e`で上書きできます。

```bash
docker compose --profile seed run --rm \
  -e SEED_ADMIN_PASSWORD=my-password \
  -e SEED_TEST_USER_PASSWORD=test-password-1234 \
  seed
```

### ⑥ 起動

```bash
docker compose up -d oidc-dev-server
```

```bash
curl http://localhost:3000/.well-known/openid-configuration
```

### ログ確認・停止

```bash
docker compose logs -f oidc-dev-server
docker compose down        # コンテナのみ停止(DB/JWKSは残る)
docker compose down -v     # ボリュームごと完全削除
```

### 注意点

`.env`を変更した際は、コンテナの**再作成**が必要です(再起動だけでは反映されません)。

```bash
docker compose up -d --force-recreate oidc-dev-server
```

詳細は`SETUP.md`の「6-2. Docker Composeでのビルド・初期化・起動」セクションに、つまずきやすいポイントの表も含めて追記済みです。
