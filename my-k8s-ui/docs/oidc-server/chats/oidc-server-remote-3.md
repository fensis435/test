## 1. `proxy`修正版のZIP

前回の`provider.proxy = env.OIDC_TRUST_PROXY`修正(`proxy`はコンストラクタオプションではなくインスタンスプロパティ)を含む最新版です。合わせて`Grant.find()`静的メソッドの型定義漏れ(今回の修正で`tsc --noEmit`を再実行して新たに発覚)も直しています。

## 2. `scripts/manage_users.rb`(新規・実機検証済み)

`register_client.rb`と同じ設計方針(標準ライブラリのみ、追加gem不要)で作成しました。

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

`--json`で生JSON出力、引数なし実行でヘルプ表示にも対応しています。

### 実機検証内容

このサンドボックス内にRuby標準の`WEBrick`でモックAPIサーバーを立て、CLIから実際にHTTPリクエストを送って以下を確認しました。

- ログイン→`list`→テーブル整形出力(正常系)
- `create`→JSON整形出力
- `list --json`(生JSON出力)
- 管理者パスワード誤り時に`401`を検知し`exit 1`で終了すること

`oidc-dev-server`本体側(TypeScript)は引き続きこのサンドボックスの制約(`binaries.prisma.sh`接続不可)によりPrisma実機起動での確認はできていませんが、今回追加した`manage_users.rb`自体はHTTPクライアントとして独立して動作検証済みです。
