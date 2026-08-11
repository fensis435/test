## 原因

`scripts/register_client.rb`(React用・Ruby単体クライアント用の両方)に**`--post-logout-redirect-uri`を指定するCLIオプションが存在せず**、`postLogoutRedirectUris`が常にデフォルト値(`http://localhost:5173/`等)のままハードコードされていました。`--redirect-uri`は正しく反映されるのに、ログアウト後のリダイレクト先だけ食い違っていたのはこのためです。

さらに、既に同じ`client_id`が登録済み(2回目以降の実行、`localhost`↔独自ドメイン間の切替時など)の場合、`409`で**何も更新せずスキップする**だけだったため、以後も毎回手動PATCHが必要になる作りでした。

## 修正内容

`oidc-web-test/scripts/register_client.rb`と`oidc-ruby-test-client/scripts/register_client.rb`の両方に、

1. `--post-logout-redirect-uri`オプションを追加
2. `--update`フラグを追加(既存Client検出時に`redirectUris`/`postLogoutRedirectUris`をPATCHで更新)

## 実機検証

WEBrickでモックAPIサーバーを立て、実際に以下を確認しました。

- `--update`なし:`409`検出後、更新せず案内メッセージを出して`exit 0`
- `--update`あり:実際に`PATCH /api/v1/clients/react-web-test-client`が送信され、レスポンスを正しく処理して`exit 0`

## 今後の運用

`localhost`↔独自ドメインを切り替える際は、1回のコマンドで完結します。

```bash
ruby scripts/register_client.rb \
  --issuer https://idp.dev.test \
  --admin-email admin@example.com \
  --admin-password change-me-please \
  --redirect-uri https://app.dev.test/callback \
  --post-logout-redirect-uri https://app.dev.test/ \
  --update
```

これで、報告いただいた②の手動`curl`は不要になります。READMEにも使い方を追記済みです。
