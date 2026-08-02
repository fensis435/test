最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
アーキテクトとしてDB設計だけを行ってください。
コードは禁止です。
SQLite + Prismaです。
必要なテーブル
Users
Groups
UserGroups
Sessions
Clients
RefreshTokens
AuthorizationCodes
WebhookLogs
について
ER図
PK
FK
Index
制約
論理削除
監査項目
まで設計してください。

---
---

# DB設計レビュー: SQLite + Prisma (OIDC開発用サーバー)

最優先要件「Cognito置き換え時のReact/Railsコード変更最小化」を踏まえ、**DBスキーマ自体はCognitoの内部データモデルに引きずられず、標準OIDC準拠のドメインモデルとして設計**します。Cognito固有の概念(UserStatus, Group Precedence等)は、テーブル本体ではなく後述のアダプタ層マッピングポリシーとして扱います。

---

## 0. ER関係(全体像)

```
Users 1───N UserGroups N───1 Groups
Users 1───N Sessions
Users 1───N RefreshTokens
Users 1───N AuthorizationCodes
Clients 1───N RefreshTokens
Clients 1───N AuthorizationCodes
Sessions 1───N RefreshTokens (nullable,任意)
RefreshTokens 1───1 RefreshTokens (自己参照: replacedByTokenId, ローテーション)
(Users/Groups/UserGroups等の変更) 1───N WebhookLogs (疎結合・FKなし)
```

WebhookLogsは意図的に他テーブルへの外部キーを持たせません。理由は後述(8番目セクション参照)。

---

## 1. Users

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID/cuid) | **PK**。OIDCの`sub`クレームと同一値として扱う |
| email | String | NOT NULL |
| normalizedEmail | String | NOT NULL, **UNIQUE**(小文字正規化済み。SQLiteは大文字小文字を区別しない一意制約を直接サポートしないための回避策) |
| emailVerified | Boolean | NOT NULL, default false |
| passwordHash | String | NOT NULL(dev用。argon2id等) |
| givenName / familyName | String? | nullable |
| status | Enum(ACTIVE, DISABLED) | NOT NULL, default ACTIVE ※Cognitoの`UserStatus`(CONFIRMED/FORCE_CHANGE_PASSWORD等)には**意図的にマッピングしない**。本番差異はadapter層で吸収する前提の最小集合 |
| createdAt | DateTime | NOT NULL, default now() |
| updatedAt | DateTime | NOT NULL, @updatedAt |
| deletedAt | DateTime? | nullable(論理削除) |
| createdByType / createdById | String? / String? | 監査(下記共通方針参照) |
| updatedByType / updatedById | String? / String? | 監査 |

**Index**
- unique(normalizedEmail)
- index(status)
- index(deletedAt) — 論理削除フィルタの高速化

**論理削除**: `deletedAt`採用。理由: Sessions/RefreshTokens/AuthorizationCodesがUsers.idを参照するため、物理削除するとトークン検証時の履歴・監査証跡(不正利用調査等)が失われる。

**制約上の注意**: SQLite/Prismaには部分ユニークインデックス(`WHERE deletedAt IS NULL`のみ一意)のネイティブサポートが弱いため、`normalizedEmail`の一意性は「論理削除されたユーザーのメールも再利用不可」という運用ルールにするか、削除時に`normalizedEmail`へサフィックスを付与して一意制約を回避する設計判断が必要。**これは今決めるべき仕様選択事項**として明記しておきます。

---

## 2. Groups

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK** |
| name | String | NOT NULL, **UNIQUE** |
| description | String? | nullable |
| createdAt / updatedAt | DateTime | 標準 |
| deletedAt | DateTime? | nullable(論理削除) |
| createdByType / createdById / updatedByType / updatedById | 監査項目 | 下記参照 |

**Index**
- unique(name)
- index(deletedAt)

**Cognito差異メモ**: CognitoのGroupには`Precedence`(優先度、複数グループ所属時の権限解決順)が存在するが、これは意図的にコア列へ追加しません。必要になった時点でアダプタ層のマッピングテーブルまたはNullable拡張列として追加する方が、コアドメインをCognito仕様から独立させる観点で健全です。

---

## 3. UserGroups(中間テーブル)

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK**(複合PKでなくsurrogate keyを採用。将来の履歴管理拡張のため) |
| userId | String | **FK → Users.id**, NOT NULL |
| groupId | String | **FK → Groups.id**, NOT NULL |
| assignedAt | DateTime | NOT NULL, default now() |
| assignedByType / assignedById | String? | 監査(誰が割り当てたか) |

**Index / 制約**
- **unique(userId, groupId)** — 複合ユニーク制約で重複所属を防止
- index(userId)
- index(groupId)

**FK onDelete**
- userId: `Restrict`(Usersは論理削除運用のため物理カスケードは基本発火しない。物理削除する場合は事前にアプリ側でUserGroupsを明示的にクリーンアップする運用とする)
- groupId: `Restrict`(同上)

**論理削除**: 採用しない(物理削除)。所属の「現在状態」を表すテーブルであり、履歴が必要なら別途`GroupMembershipEvents`(追記専用ログ)を切り出すのが筋が良い。今回のスコープでは省略。

---

## 4. Sessions

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK** |
| userId | String | **FK → Users.id**, NOT NULL |
| sessionTokenHash | String | NOT NULL, **UNIQUE**(生トークンは保存しない) |
| userAgent | String? | nullable、監査/不正検知用 |
| ipAddress | String? | nullable |
| issuedAt | DateTime | NOT NULL, default now() |
| expiresAt | DateTime | NOT NULL |
| lastActivityAt | DateTime | NOT NULL |
| revokedAt | DateTime? | nullable(論理失効) |

**Index**
- unique(sessionTokenHash)
- index(userId, expiresAt)
- index(revokedAt)

**FK onDelete**: userId → `Cascade`(セッションはUser本体より寿命が短く、監査上の保持価値も限定的なため物理カスケードで問題なし。ただしUsersは論理削除運用なので実質的にはアプリ側でのセッション失効処理が主となる)

**論理削除に代わる方針**: `revokedAt`をセッションの実効的な"削除"として扱う。物理行はTTL経過後のバッチ削除(パージジョブ)で掃除する運用を推奨。`deletedAt`と`revokedAt`を両方持つのは冗長なため統一。

---

## 5. Clients(OIDC RP登録。Cognito App Client相当)

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK**(内部主キー) |
| clientId | String | NOT NULL, **UNIQUE**(OIDCプロトコル上のclient_id、外部公開値) |
| clientSecretHash | String? | nullable(PublicクライアントであるReactはnull。Rails側が confidential clientとして使う場合のみ設定) |
| isPublic | Boolean | NOT NULL(PKCE前提のpublic clientフラグ) |
| tokenEndpointAuthMethod | Enum(NONE, CLIENT_SECRET_BASIC, CLIENT_SECRET_POST) | NOT NULL |
| redirectUris | String(JSON配列をtextで保存) | NOT NULL |
| postLogoutRedirectUris | String(JSON) | NOT NULL, default `[]` |
| allowedScopes | String(JSON) | NOT NULL |
| grantTypes | String(JSON) | NOT NULL(`authorization_code`, `refresh_token`) |
| createdAt / updatedAt | DateTime | 標準 |
| deletedAt | DateTime? | nullable(論理削除) |

**Index**
- unique(clientId)
- index(deletedAt)

**制約**: `isPublic = true`の場合`clientSecretHash`はNULLでなければならない、という業務ルールはDB制約(CHECK)ではなくアプリ層バリデーションで担保(SQLiteのCHECK制約自体は可能だがPrisma経由では表現力が限定的なため)。

---

## 6. RefreshTokens

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK** |
| tokenHash | String | NOT NULL, **UNIQUE**(生トークンは保存しない) |
| familyId | String | NOT NULL(ローテーション検知用。同一発行系列を束ねるID) |
| userId | String | **FK → Users.id**, NOT NULL |
| clientId | String | **FK → Clients.id**, NOT NULL |
| sessionId | String? | **FK → Sessions.id**, nullable |
| replacedByTokenId | String? | **FK → RefreshTokens.id(自己参照)**, nullable |
| scope | String | NOT NULL |
| issuedAt | DateTime | NOT NULL |
| expiresAt | DateTime | NOT NULL |
| revokedAt | DateTime? | nullable |
| revokedReason | String? | nullable(`ROTATED`, `REUSE_DETECTED`, `USER_LOGOUT`等) |

**Index**
- unique(tokenHash)
- index(userId)
- index(clientId)
- index(familyId) — reuse検知(同一family内で既にrevoke済みトークンが再提示されたら家系全体を失効させる)のために必須
- index(expiresAt) — 期限切れパージバッチ用

**FK onDelete**
- userId, clientId: `Restrict`(トークンが残っている状態でのUser/Client物理削除を防止。削除前に明示revoke必須)
- sessionId: `SetNull`
- replacedByTokenId: `SetNull`

**論理削除**: 採用せず`revokedAt`で管理。理由: RefreshTokensは本質的に「有効/失効」の状態機械であり、論理削除フラグと失効フラグを分けると意味が重複する。

---

## 7. AuthorizationCodes

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK** |
| codeHash | String | NOT NULL, **UNIQUE** |
| userId | String | **FK → Users.id**, NOT NULL |
| clientId | String | **FK → Clients.id**, NOT NULL |
| redirectUri | String | NOT NULL(token交換時の完全一致検証用) |
| codeChallenge | String | NOT NULL(PKCE) |
| codeChallengeMethod | Enum(S256, PLAIN) | NOT NULL, default S256 |
| scope | String | NOT NULL |
| nonce | String? | nullable(OIDC) |
| expiresAt | DateTime | NOT NULL(短TTL, 目安60〜600秒) |
| usedAt | DateTime? | nullable(単一使用フラグ) |
| createdAt | DateTime | NOT NULL |

**Index**
- unique(codeHash)
- index(clientId, userId)
- index(expiresAt) — 期限切れパージ用

**FK onDelete**: userId, clientId → `Cascade`(寿命が極めて短く、監査上の保持価値が低いため物理カスケードで問題ない)

**論理削除**: 採用しない。`usedAt`が単一使用制約の実効的な状態管理。**リプレイ攻撃検知の観点では、`usedAt`が既に設定済みのコードが再度使用された場合、そのクライアントに紐づく発行済みトークン群を一括失効させるロジックをアプリ層に必ず実装する**(RFC推奨の防御)。

---

## 8. WebhookLogs

| 項目 | 型 | 制約 |
|---|---|---|
| id | String (UUID) | **PK** |
| eventType | String | NOT NULL(`user.created`, `user.updated`, `user.deleted`, `group.membership.changed`等) |
| targetUrl | String | NOT NULL |
| payload | String(JSON) | NOT NULL |
| status | Enum(PENDING, SUCCESS, FAILED, RETRYING) | NOT NULL, default PENDING |
| httpStatusCode | Int? | nullable |
| attemptCount | Int | NOT NULL, default 0 |
| lastAttemptAt | DateTime? | nullable |
| nextRetryAt | DateTime? | nullable |
| responseBodySnippet | String? | nullable(デバッグ用、長さ制限して保存) |
| createdAt | DateTime | NOT NULL |

**Index**
- index(status, nextRetryAt) — リトライワーカーのポーリングクエリ用
- index(eventType, createdAt)

**意図的にFKを持たせない設計理由**: WebhookLogsは「誰に何を通知しようとしたか」の事実記録であり、対象のUser/Groupが論理削除・物理削除された後もログとして残る必要がある(通知失敗の事後調査、監査対応)。FK制約で縛ると削除順序に強く依存してしまうため、`payload`内にJSON形式で対象IDを埋め込む疎結合設計を採用します。

**論理削除**: 採用しない。追記専用(append-only)ログとして扱い、保持期間はアプリ側の定期パージジョブ(例: 90日超過分を削除)で管理する。

---

## 監査項目の共通方針

全テーブルに`createdAt`/`updatedAt`は必須としつつ、「誰が行ったか」の記録は次の理由で**単純なUsers.idへのFKにしない**ことを推奨します。

- OIDCフロー自体(コード発行、トークン発行)はシステム自身が行うため、「actor = User」とは限らない
- 将来Cognito Adapter経由の操作(AWS API経由の管理操作等)が主体になった場合、actorの種類が増える

そのため以下の2カラムの組を監査系フィールドの共通パターンとして提案します。

| カラム | 型 | 説明 |
|---|---|---|
| `xxxByType` | Enum(SYSTEM, ADMIN_USER, API_CLIENT) | 誰(何)が操作したかの種別 |
| `xxxById` | String? | 種別に応じたID(ADMIN_USERならUsers.id、API_ClientならClients.id、SYSTEMならnull) |

これはFKを張らない緩い参照(アプリ層で整合性検証)とし、Users/Clientsの論理削除・将来的な入れ替えに対して監査ログ側が固く結合しすぎないようにする設計判断です。

---

## Cognito移行時の設計上の配慮(このDB設計固有の論点)

1. **`Users.id` = `sub`前提の設計**: CognitoのsubはUUID形式のため、開発DBのUsers.idも最初からUUID文字列にしておくことで、移行時のUser識別子の型不一致を回避しています。
2. **User CRUD / WebhookLogsはコアOIDCテーブル群と物理的に疎結合**: Clients/RefreshTokens/AuthorizationCodesの検証系テーブルは標準OIDCの実装詳細としてそのまま残存させられますが、Users/Groups/UserGroups/WebhookLogsは「本番ではCognito側のデータになる、または存在しない概念になる」テーブル群です。**この境界線は前回レビューで示したPort & Adapter設計と完全に対応しており、DBスキーマ設計時点からこの境界を崩さないことが最優先要件の担保につながります。**
3. **Groupsに`precedence`等のCognito固有属性を先回りで追加しない**: 必要になった時点で追加する。先回り追加は「Cognitoの都合がコアドメインに漏れる」アンチパターンです。

---

**一点確認したいのですが**、RefreshTokensの`familyId`によるローテーション再利用検知(reuse detection)は、開発用サーバーとしてどこまで厳密に実装する想定でしょうか。本番Cognitoは同等の防御をトークンの内部実装で行っており外部からは見えない挙動のため、開発側でどこまで模倣するかによって`revokedReason`の設計粒度が変わってきます。
