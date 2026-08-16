# ユーザー同期アーキテクチャ(Cognito/oidc-dev-server -> SQS -> Backend)

## 全体構成

```
【AWS本番環境】(将来。今回のスコープ外だが構造は同じ)
[管理者] -> [Cognito AdminCreateUser等] -> [CloudTrail] -> [EventBridge] -> [実SQS] -> [Rails: bin/sqs_poller]

【このリポジトリでの開発/検証環境】
[Management API呼び出し] -> [oidc-dev-server] -> [cloudtrail-event-builder.ts] -> [ElasticMQ(SQS互換)] -> [Rails: bin/sqs_poller]
                                                                                                              |
                                                                                                              v
                                                                                                    [UserSyncApplicationService]
                                                                                                              |
                                                                                                              v
                                                                                                      [SyncedUser (仮のユーザーDB)]

【オンプレ環境】(既存実装。このリポジトリの外)
[WebGUI] -> [REST Controller] -> [UserSyncApplicationService] -> [ユーザーDB]
             (app/controllers/api/v1/admin/users_controller.rb が最小デモ)
```

## Ports and Adapters(ヘキサゴナルアーキテクチャ)のマッピング

| 役割 | このリポジトリでの実装 |
|---|---|
| Port(駆動ポート) | `app/ports/user_sync_use_case.rb` (`UserSyncUseCase`) |
| コアロジック(Portの実装) | `app/services/user_sync_application_service.rb` (`UserSyncApplicationService`) |
| 駆動アダプタ(SQS) | `app/adapters/sqs_user_event_adapter.rb` (`SqsUserEventAdapter`) |
| 駆動アダプタ(REST、デモ) | `app/controllers/api/v1/admin/users_controller.rb` |
| 共通イベント構造 | `app/value_objects/user_change_event.rb` (`UserChangeEvent`) |
| 仮のユーザーDB | `app/models/synced_user.rb` (`SyncedUser`) |
| 冪等性担保用テーブル | `app/models/processed_event.rb` (`ProcessedEvent`) |

**入力元(SQS / REST)ごとの差異は、それぞれのAdapterが`UserChangeEvent`への変換として吸収する。`UserSyncApplicationService`はSQSのメッセージ形式もCloudTrailのJSON構造もHTTPパラメータの形状も一切知らない。** これにより、将来オンプレの既存REST実装をこの構造に合わせて移行する際も、コアロジック自体は無改修で使い回せる。

## Cognito CloudTrailイベント形式との対応

`oidc-dev-server`の`src/adapters/cognito-compat/cloudtrail-event-builder.ts`が、内部イベント(`user.created`等)を実際のCognito Admin API呼び出しがCloudTrail経由でEventBridge/SQSに届く場合と同じ形状のJSONに変換する。

| 内部イベント種別 | Cognito eventName |
|---|---|
| `user.created` | `AdminCreateUser` |
| `user.updated` | `AdminUpdateUserAttributes` |
| `user.deleted` | `AdminDeleteUser` |
| `user.enabled` | `AdminEnableUser` |
| `user.disabled` | `AdminDisableUser` |
| `user.password_set` | `AdminSetUserPassword` |
| `user.password_reset` | `AdminResetUserPassword` |
| `group.membership.changed` (action: added) | `AdminAddUserToGroup` |
| `group.membership.changed` (action: removed) | `AdminRemoveUserFromGroup` |

メッセージ全体はEventBridgeの標準的なイベント封筒(`version`, `id`, `detail-type`, `source`, `account`, `time`, `region`, `resources`, `detail`)に、CloudTrail管理イベントの`detail`(`eventName`, `requestParameters`, `responseElements`, `eventTime`, `eventID`等)を格納した形になっている。

## 「3つの注意点」への対応

### 1. 同期(Sync) vs 非同期(Async)のレスポンス設計

- **SQSアダプタ**(`app/adapters/sqs_user_event_adapter.rb`): 完全非同期。処理成功時のみメッセージを明示的に削除し、失敗時は**意図的に削除しない**。SQSのVisibility Timeout経過後に自動再配信され、冪等性ガードにより安全に再試行される。
- **RESTアダプタ**(`app/controllers/api/v1/admin/users_controller.rb`、デモ): 同期的に`UserSyncApplicationService`を呼び、結果に応じて即座に200/400を返す。クライアント(WebGUI)に失敗を明示的に伝える必要があるため、SQSアダプタとは異なる方針を意図的に採用している。

この差異は各Adapter内に閉じており、`UserSyncApplicationService`自体はどちらの方針で呼ばれるかを一切意識しない。

### 2. 冪等性(Idempotency)の担保

`UserSyncApplicationService#sync_user_change`は、トランザクション内でまず`ProcessedEvent.create!(event_id: ...)`を試みる。同じ`event_id`が既に存在すれば`ActiveRecord::RecordNotUnique`が発生し、`:skipped_duplicate`を返して処理を打ち切る。

`event_id`はCloudTrailの`eventID`(Cognito実本番でも一意)、またはoidc-dev-server側で`randomUUID()`により生成した値を使うため、同一イベントの重複配信を確実に検知できる。

### 3. イベントの順序保証

`SyncedUser`テーブルに`source_event_time`カラムを持たせ、`UserSyncApplicationService`は新しいイベントを適用する前に「そのユーザーの既存レコードが持つ`source_event_time`より新しいか」を`SyncedUser#stale_event?`で判定する。古いイベントであれば`:skipped_stale`を返し、DBの状態を上書きしない。

## ローカルでの動作確認手順

### ① ElasticMQの起動

```bash
cd oidc-dev-server
docker compose up -d elasticmq
```

管理UI: `http://localhost:9325`(`softwaremill/elasticmq-native`イメージに
標準で内蔵されているUI。Docker Hub公式説明で「9325 is the default UI port」
と明記されている)でキューの中身を確認できる。

### ② oidc-dev-server側の設定

`.env`に以下を追加(コメントアウトを外す):

```
SQS_QUEUE_URL=http://localhost:9324/queue/cognito-user-events
SQS_ENDPOINT=http://localhost:9324
```

**キューURLの形式について**: ElasticMQ公式README(2026年時点の最新版で確認済み)
によれば、既定の`node-address`設定では
`http://<host>:<port>/queue/<queue名>`という形式でキューURLが生成される。
`elasticmq.conf`で`node-address.host = "*"`を指定している場合
(このプロジェクトの設定はこの方式)、URLのホスト部分は実際に受けた
リクエストのホストがそのまま使われる(公式README「How are queue URLs
created」の節に「containerized (Docker) deployments で有用」と明記されている
挙動)。oidc-dev-server・Rails側のいずれも`http://localhost:9324`経由で
アクセスする限り、上記の`SQS_QUEUE_URL`の値で一致する。

万一のバージョン差異に備え、起動後に一覧を直接確認することもできる。

```bash
curl -X POST http://localhost:9324/ \
  -d "Action=ListQueues" \
  -H "Content-Type: application/x-www-form-urlencoded"
# または管理UI (http://localhost:9325) でキュー一覧を確認
```

### ③ Rails側の設定

`backend/.env`に同様の設定を追加(`.env.example`に既定値あり)。

```bash
cd backend
bundle install    # sqlite3, aws-sdk-sqs等が追加されているため再実行が必要
bin/rails db:migrate
```

### ④ ポーラーの起動

```bash
bin/sqs_poller
```

### ⑤ 動作確認

`oidc-dev-server`側でユーザーを作成する(`scripts/manage_users.rb create`等)と、`bin/sqs_poller`のログに処理結果が表示され、`SyncedUser`テーブルにレコードが作成される。

```bash
# oidc-dev-server側で
ruby scripts/manage_users.rb create --email sync-test@example.com --password correct-horse-battery

# Rails側で確認
bin/rails runner "pp SyncedUser.all"
```

## 実装後の自己レビューで発見・修正した問題

Ruby側は実機実行できないため、追加のコードレビューを行い以下を発見・修正した。

- **`UserSyncApplicationService#sync_user_change`**: `ActiveRecord::Base.transaction do ... end` ブロック内で `return` を使っていた。これはRails/Rubyでよく知られた落とし穴で、Railsのバージョンによってトランザクションのコミット/ロールバック挙動に意図しない影響を与えることがある。`next` + ブロック外のローカル変数に結果を格納するパターンに書き換えた(この`next`/`return`の挙動差自体はRubyの素の挙動として実際に動かして検証済み)。

## 未検証の項目(正直な申告)

このサンドボックス環境は`rubygems.org`への接続が制限されているため、以下は**構文チェックのみ**で、実際の`bundle install`・DB接続・SQS送受信を伴う動作確認はできていません。

- `UserSyncApplicationService`の冪等性・順序保証ロジックの実DB(SQLite)での動作
- `SqsUserEventAdapter`の`aws-sdk-sqs`経由でのElasticMQとの実通信
- `bin/rails db:migrate`によるマイグレーション実行そのもの

一方、Node.js側の`cloudtrail-event-builder.ts`(内部イベント -> CloudTrail/EventBridge形状JSON変換)は実際に実行し、全アサーションがPASSすることを確認済みです。お手元の環境で`bundle install`以降を実行した際に何か問題が出れば、これまでと同じように詳細を共有してください。
