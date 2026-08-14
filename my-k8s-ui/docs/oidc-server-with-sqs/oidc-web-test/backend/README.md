# rails-token-verifier (Rails v8 API)

`oidc-web-test` の一部。React(Vite)から送られてきたAccess Tokenを
JWKS経由で検証するだけの、最小構成のRails v8 APIアプリです。

## このアプリが持たないもの(意図的)

- ActiveRecord(DBを一切使わない)
- ビュー/アセットパイプライン(`config.api_only = true`)
- セッションCookie(認証情報はAuthorizationヘッダのみで受け渡す)

`require "rails/all"` ではなく `action_controller/railtie` のみを
読み込んでいます(`config/application.rb` 参照)。トークン検証専用の
テストアプリに不要な依存を持ち込まない、という設計判断です。

## セットアップ

```bash
bundle install
cp .env.example .env
```

## 起動

```bash
bin/rails server
# または
bundle exec puma -C config/puma.rb
```

デフォルトで `http://localhost:3001` で待ち受けます。

## 動作確認

```bash
# 200 OKが返ればRails自体は起動している
curl http://localhost:3001/up

# トークンなしで呼ぶと401になることの確認
curl -i http://localhost:3001/api/v1/whoami

# 実際のAccess Tokenを使う場合(Reactでログイン後、ブラウザのdevtoolsで
# sessionStorageから access_token を取得するか、oidc-ruby-test-client等で取得したものを使う)
curl -i http://localhost:3001/api/v1/whoami \
  -H "Authorization: Bearer <access_token>"
```

## Cognito移行時の変更範囲

`config/initializers/oidc.rb` の `OIDC_ISSUER` をCognito User PoolのURLに
変更するだけです。`TokenVerifier`(`app/services/token_verifier.rb`)は
issuer以外のURLをハードコードしておらず、Discoveryドキュメント経由で
`jwks_uri`を再解決するため、コード変更は不要です。

## [追加] Cognito/oidc-dev-server -> SQS -> Backend ユーザー同期

`bin/sqs_poller` を起動すると、oidc-dev-server(またはCognito本番)から
発行されるユーザーライフサイクルイベントをSQS経由でポーリングし、
仮のユーザーDB(`SyncedUser`)に反映する。

Ports and Adaptersパターンでの実装詳細、3つの設計上の注意点
(同期/非同期・冪等性・順序保証)への対応、動作確認手順は
`../USER_SYNC_ARCHITECTURE.md` を参照。
