>RefreshTokensの`familyId`によるローテーション再利用検知(reuse detection)は、開発用サーバーとしてどこまで厳密に実装する想定でしょうか。
上記に対する回答は「厳密である必要はない」です。
---
最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
REST API設計のみを行ってください。
コードは禁止です。
以下を定義してください。
User CRUD
Password
Enable
Disable
Groups
Login
Logout
Webhook
OpenAPI形式で
Request
Response
Error
HTTP Status
Validation
まで設計してください。

---
---

# REST API設計: Identity Management API(OIDC開発用サーバー)

最優先要件に基づき、まず**API群の位置づけを明確化**します。これが今回の設計における最も重要な決定です。

## 0. 前提: このAPIはReactから直接呼ばれてはならない

以下で定義する全エンドポイントは **`Management API`** であり、想定呼び出し元は **Rails(バックエンド経由)または運用ツールのみ** です。

- 標準OIDCエンドポイント(`/.well-known/openid-configuration`, `/authorize`, `/token`, `/userinfo`, `/jwks.json`, RP-Initiated Logout)は本設計の対象外(前回までに設計済みのOIDC Core)。**Reactはこちらのみを使用する。**
- 本設計の User CRUD / Password / Enable / Disable / Groups / Webhook / (後述する)Login・Logoutは、**Cognito本番環境には存在しないか、AWS Admin API/Lambdaトリガーという全く異なる形態に置き換わる領域**です。
- したがって、これらは必ず **RailsのIdentityManagementPort実装からのみ叩かれる**構造とし、Reactからの直接呼び出しを設計・レビュー双方で禁止します。もしReactが直接叩く実装が出てきたら、それは最優先要件違反として即座に指摘すべきです。

ベースパス: `/api/v1`
認証: `Authorization: Bearer <admin_access_token>`(このManagement API自体を保護するための、User向けOIDCトークンとは別の管理者用トークン)

---

## 共通設計

### エラーフォーマット(RFC 7807 準拠)

全エラーレスポンスは`application/problem+json`で統一します。

| フィールド | 型 | 説明 |
|---|---|---|
| type | string(URI) | エラー種別を示すURI(例: `https://idp.internal/errors/validation-error`) |
| title | string | 人間可読な短い要約 |
| status | integer | HTTPステータスコードと一致 |
| detail | string | 詳細メッセージ |
| instance | string | 発生したリクエストパス |
| errors | array | バリデーションエラー時のフィールド単位の詳細(下記) |

`errors[]`の要素:

| フィールド | 型 | 説明 |
|---|---|---|
| field | string | 対象フィールド名(例: `email`) |
| code | string | `REQUIRED` / `INVALID_FORMAT` / `TOO_LONG` / `DUPLICATE` 等 |
| message | string | フィールド単位のメッセージ |

### 共通HTTPステータス方針

| ステータス | 用途 |
|---|---|
| 200 | 取得・更新成功 |
| 201 | 作成成功(`Location`ヘッダー必須) |
| 204 | 削除・状態変更等、レスポンスボディなしの成功 |
| 400 | リクエストバリデーションエラー |
| 401 | 管理者トークン未認証・無効 |
| 403 | 権限不足 |
| 404 | リソース不存在(論理削除済みを含む) |
| 409 | 一意制約違反・状態競合(例: 既にenable済み) |
| 422 | 意味的に不正(例: グループ未所属からの削除試行) |
| 429 | レート制限超過 |
| 500 | サーバー内部エラー |

### 共通ページネーション(一覧系エンドポイント)

クエリパラメータ: `limit`(default 20, max 100)、`cursor`(opaque string)
レスポンス共通ラッパー:

| フィールド | 型 | 説明 |
|---|---|---|
| items | array | 結果配列 |
| nextCursor | string\|null | 次ページカーソル。nullなら最終ページ |

---

## 1. User CRUD

### POST /api/v1/users — ユーザー作成

**Request Body**

| フィールド | 型 | 必須 | Validation |
|---|---|---|---|
| email | string | ✓ | RFC5322形式、最大254文字 |
| givenName | string | – | 最大100文字 |
| familyName | string | – | 最大100文字 |
| temporaryPassword | string | ✓ | 最小8文字、英数字記号混在(dev用簡易ポリシー) |
| groupIds | array\<string\> | – | 各要素はGroups.idとして存在すること |

**Response 201**

| フィールド | 型 |
|---|---|
| id | string(uuid) |
| email | string |
| status | `ACTIVE`\|`DISABLED` |
| createdAt | string(ISO8601) |

**Error**
- 400: email形式不正、temporaryPassword不足
- 409: `normalizedEmail`重複(`code: DUPLICATE`)
- 422: 存在しないgroupIdsを指定

---

### GET /api/v1/users — ユーザー一覧

**Request(Query)**

| パラメータ | 型 | 必須 | Validation |
|---|---|---|---|
| email | string | – | 部分一致検索 |
| status | `ACTIVE`\|`DISABLED` | – | enum検証 |
| groupId | string | – | Groups.id存在検証 |
| limit / cursor | 共通ページネーション | – | – |

**Response 200**: 共通ページネーションラッパー、`items[]`は下記GET単体と同一スキーマ(パスワード等の機微情報は含まない)。

---

### GET /api/v1/users/{userId} — ユーザー詳細

**Response 200**

| フィールド | 型 |
|---|---|
| id | string |
| email | string |
| emailVerified | boolean |
| givenName / familyName | string\|null |
| status | `ACTIVE`\|`DISABLED` |
| groups | array\<{id, name}\> |
| createdAt / updatedAt | string(ISO8601) |

**Error**: 404(存在しない、または論理削除済み)

---

### PATCH /api/v1/users/{userId} — ユーザー更新(部分更新)

**Request Body**(すべてoptional、指定フィールドのみ更新)

| フィールド | 型 | Validation |
|---|---|---|
| givenName | string | 最大100文字 |
| familyName | string | 最大100文字 |
| email | string | RFC5322形式、変更時は`emailVerified`を自動的にfalseへ |

**Response 200**: GET単体と同一スキーマ
**Error**: 400(形式不正)、404、409(email重複)

---

### DELETE /api/v1/users/{userId} — ユーザー削除(論理削除)

**Response 204**(ボディなし)

**Error**: 404、409(有効なRefreshTokens/Sessionsが残存する場合は事前失効が必要 — `code: ACTIVE_TOKENS_EXIST`。アプリ側で自動失効させるか409で拒否するかは実装ポリシーとして要決定。今回は**自動失効(カスケード的にrevoke)を採用し、409は返さない**方針を推奨)

**設計メモ**: 物理削除ではなく`deletedAt`設定。削除後は`normalizedEmail`にサフィックスを付与するか、削除済みメールの再登録を拒否するかを運用ポリシーとして明記(前回のDB設計で保留した論点)。ここでは**削除時にemailへタイムスタンプサフィックスを付与し、新規登録での再利用を許可する**方式を採用します。

---

## 2. Password

### PUT /api/v1/users/{userId}/password — 管理者によるパスワード強制設定

**Request Body**

| フィールド | 型 | 必須 | Validation |
|---|---|---|---|
| newPassword | string | ✓ | 最小8文字 |
| requireChangeOnNextLogin | boolean | – | default false(dev用の簡易フラグ。Cognitoの`FORCE_CHANGE_PASSWORD`相当だが、コア外のオプション扱い) |

**Response 204**
**Error**: 400、404

### POST /api/v1/users/{userId}/password/reset-token — パスワードリセットトークン発行

**Response 201**

| フィールド | 型 |
|---|---|
| resetToken | string |
| expiresAt | string(ISO8601)(推奨: 発行後30分) |

### POST /api/v1/password/reset — リセットトークンによる新パスワード設定(ユーザー本人操作)

**Request Body**

| フィールド | 型 | 必須 | Validation |
|---|---|---|---|
| resetToken | string | ✓ | 有効期限内・未使用であること |
| newPassword | string | ✓ | 最小8文字 |

**Response 204**
**Error**: 400(トークン期限切れ/使用済み → `code: TOKEN_EXPIRED` / `code: TOKEN_ALREADY_USED`)、404(トークン不存在)

---

## 3. Enable / Disable

### POST /api/v1/users/{userId}/enable

**Request Body**: なし
**Response 200**

| フィールド | 型 |
|---|---|
| id | string |
| status | `ACTIVE` |

**Error**: 404、409(既にACTIVEの場合 `code: ALREADY_ACTIVE`。冪等性を重視するなら200で許容する設計も可。**今回は冪等成功(200)を採用**しエラーにしない方針を推奨)

### POST /api/v1/users/{userId}/disable

**Response 200**: 同上スキーマ、`status: DISABLED`

**設計メモ**: Disable時は**同時に該当ユーザーの有効なSessions/RefreshTokensを全失効**させる(サイドエフェクトとして明記)。これはCognitoの`AdminDisableUser`が既存トークンの有効性に影響を与えない点と挙動が異なるため、**アダプタ層で吸収すべき差異としてADRに記録すること**を推奨します。

---

## 4. Groups

### POST /api/v1/groups

**Request Body**

| フィールド | 型 | 必須 | Validation |
|---|---|---|---|
| name | string | ✓ | 最大128文字、一意 |
| description | string | – | 最大500文字 |

**Response 201** / **Error**: 400、409(name重複)

### GET /api/v1/groups, GET /api/v1/groups/{groupId}, PATCH /api/v1/groups/{groupId}, DELETE /api/v1/groups/{groupId}

Users CRUDと同一パターン(一覧・詳細・部分更新・論理削除)。バリデーション・エラーコードも同様の形式。

### POST /api/v1/users/{userId}/groups/{groupId} — グループ所属追加

**Request Body**: なし
**Response 204**
**Error**: 404(user/group不存在)、409(既に所属済み `code: ALREADY_MEMBER`。**冪等成功として204を返す**方針を推奨)

### DELETE /api/v1/users/{userId}/groups/{groupId} — グループ所属解除

**Response 204**
**Error**: 404(所属関係が存在しない場合 `code: NOT_MEMBER`)

### GET /api/v1/users/{userId}/groups — 所属グループ一覧

**Response 200**: `items: array<{id, name, assignedAt}>`

---

## 5. Login / Logout ── ⚠️設計上の重要な注意

ここは最優先要件に対して最もリスクが高い領域なので、先に方針を明示します。

> **`/api/v1/auth/login` は「管理者がこのManagement APIを使うための認証」または「開発・テスト自動化用のROPC的な簡易ログイン」であり、エンドユーザー(Reactアプリ利用者)の認証手段ではありません。** エンドユーザー認証は必ず標準OIDC `/authorize`(Authorization Code + PKCE)を使用してください。もしReact側がこのエンドポイントを直接呼ぶ実装になっていたら、それは設計逸脱であり、Cognito移行時に確実にコード書き換えが発生します。

### POST /api/v1/auth/login(開発・テストツール専用、ROPC相当)

**Request Body**

| フィールド | 型 | 必須 | Validation |
|---|---|---|---|
| email | string | ✓ | RFC5322形式 |
| password | string | ✓ | 空文字不可 |

**Response 200**

| フィールド | 型 |
|---|---|
| sessionId | string |
| accessToken | string(管理API用) |
| expiresAt | string(ISO8601) |

**Error**
- 400: 必須項目不足
- 401: 認証失敗(`code: INVALID_CREDENTIALS`。ユーザー列挙攻撃対策として、ユーザー不存在時も同一メッセージ)
- 403: `status: DISABLED`のユーザーによるログイン試行

### POST /api/v1/auth/logout

**Request(Header)**: `Authorization: Bearer <accessToken>`
**Response 204**
**Error**: 401(無効なトークン)

**設計メモ**: このエンドポイントはCognito本番には対応物が存在しません(Cognitoにおけるエンドユーザーのログアウトは、標準OIDCのRP-Initiated LogoutをReactが直接呼ぶ形になる)。したがって本エンドポイントは**移行時に単純削除される想定**であり、Rails側でもし依存する場合は「管理API自体の認証」という別のライフサイクルとして完全に分離しておくことを強く推奨します。

---

## 6. Webhook

### POST /api/v1/webhooks — Webhook登録

**Request Body**

| フィールド | 型 | 必須 | Validation |
|---|---|---|---|
| targetUrl | string(URI) | ✓ | https必須(dev環境除く)、最大2048文字 |
| eventTypes | array\<string\> | ✓ | 許可値: `user.created`, `user.updated`, `user.deleted`, `user.enabled`, `user.disabled`, `group.membership.changed` から1つ以上 |
| secret | string | – | 署名検証用(HMAC)。未指定ならサーバー側自動生成 |
| active | boolean | – | default true |

**Response 201**

| フィールド | 型 |
|---|---|
| id | string |
| targetUrl | string |
| eventTypes | array\<string\> |
| active | boolean |
| createdAt | string(ISO8601) |

**Error**: 400(URI形式不正、eventTypes空配列/不正値)

### GET /api/v1/webhooks, GET /api/v1/webhooks/{id}, PATCH /api/v1/webhooks/{id}, DELETE /api/v1/webhooks/{id}

Users/Groupsと同一パターン。

### POST /api/v1/webhooks/{id}/test — テスト送信

**Response 200**

| フィールド | 型 |
|---|---|
| delivered | boolean |
| httpStatusCode | integer\|null |
| latencyMs | integer |

**Error**: 404、502(送信先接続失敗 `code: DELIVERY_FAILED`)

### GET /api/v1/webhooks/{id}/logs — 配信ログ一覧

**Request(Query)**: `status`(`PENDING`\|`SUCCESS`\|`FAILED`\|`RETRYING`), 共通ページネーション

**Response 200**: `items: array<{id, eventType, status, httpStatusCode, attemptCount, lastAttemptAt, createdAt}>`

**設計メモ**: 前回のDB設計通りWebhookLogsは対象リソースへのFKを持たないため、`payload`内のIDでの絞り込みが必要な場合は別途`targetResourceId`クエリパラメータの追加を検討(payloadのJSON内検索はSQLiteでは非効率なため、必要になった時点で非正規化列を足す判断でよい)。

---

## Cognito移行時のAPI差異まとめ(このAPI設計固有)

| 本設計のAPI | Cognito本番での対応 | 移行時の扱い |
|---|---|---|
| User CRUD | AWS SDK `AdminCreateUser`等(REST形状が根本的に異なる) | RailsのIdentityManagementPort実装を差し替え。ポート自体のインターフェースは維持可能 |
| Password | `AdminSetUserPassword`等 | 同上 |
| Enable/Disable | `AdminEnableUser`/`AdminDisableUser` | 同上。ただし前述の「トークン自動失効」という副作用の差異に注意 |
| Groups | `AdminAddUserToGroup`等 | 同上 |
| Login(管理API用) | 対応物なし | **管理API自体の認証手段を別途設計し直す必要あり(このエンドポイントは廃止対象)** |
| Logout(管理API用) | 対応物なし(エンドユーザーのRP-Initiated LogoutはOIDC Core側で対応済み) | 同上、廃止対象 |
| Webhook | Lambdaトリガー(同期呼び出し、HTTPSエンドポイント形式ではない) | Webhook登録/配信ロジックはアダプタ層でLambda連携に置き換え。RailsのUserLifecycleEventPort(イベント受信インターフェース)自体は維持できる設計を前回提案済み |

---

一点確認させてください。`/api/v1/auth/login`(管理API用ログイン)について、これは**Railsが管理操作を行う際のサービス間認証**として使う想定でしょうか、それとも**人間の管理者がツールから使う想定**でしょうか。前者であれば「Client Credentials的な仕組み」に置き換えた方がOIDC標準に寄せられ設計がシンプルになりますが、後者であれば現状のemail/passwordログイン形式が実務上妥当です。想定利用者によってこのAPIの認可モデル(トークンの寿命・スコープ設計)が変わってきます。

