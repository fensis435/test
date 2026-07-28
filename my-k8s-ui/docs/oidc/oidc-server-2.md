これは私も普段LLMで大きなシステムを作るときにやる方法ですが、**「コードを書かせないフェーズ」を設ける**のが一番効果があります。

一発で「全部作れ」はほぼ失敗します。

私なら以下の7プロンプトに分割します。

---

# Prompt1 アーキテクチャレビュー

```text
あなたはOAuth2/OIDCおよびNode.jsのPrincipal Architectです。

コードは一切書かないでください。

これから開発用OIDC Serverを作ります。

目的はAWS Cognito Hosted UIの代替です。

React(Vite)+oidc-client-ts
Rails8(API)

から利用されます。

本番ではCognitoへ切替えます。

要求は

・Authorization Code + PKCE
・Discovery
・JWKS
・User CRUD
・Webhook通知
・SQLite
・Kubernetes

です。

以下についてレビューしてください。

1. システム構成
2. 責務分割
3. ディレクトリ構成
4. DDD観点
5. SOLID観点
6. 将来Cognitoへ置き換える際の差異
7. リスク
8. 改善案

コードは禁止です。
```

---

# Prompt2 DB設計

```text
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
```

---

# Prompt3 API設計

```text
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
```

---

# Prompt4 OIDC設計

```text
OIDC Provider設計のみを行ってください。

コードは禁止です。

以下を設計してください。

Authorization Code Flow

PKCE

Discovery

JWKS

Claims

Scopes

Consent

Session

Cookie

Logout

Refresh Token

oidc-providerの設定方針も説明してください。

Cognitoとの差異もまとめてください。
```

---

# Prompt5 実装

```text
これまでの設計をすべて採用してください。

勝手に仕様変更は禁止です。

Node.js22

TypeScript

Express

oidc-provider

Prisma

SQLite

で実装してください。

出力は

ディレクトリ単位

ファイル単位

で行ってください。

コードは省略禁止です。

途中で止めず最後まで出力してください。
```

---

# Prompt6 Docker/Kubernetes

```text
実装済コードを前提として

Dockerfile

docker-compose.yml

Kubernetes

を作成してください。

Kubernetesは

Deployment

Service

Ingress

PVC

ConfigMap

Secret

NetworkPolicy

PodDisruptionBudget

Resource

Probe

まで作成してください。

ベストプラクティスでお願いします。
```

---

# Prompt7 レビュー

```text
Principal Engineerとしてレビューしてください。

コードは変更しません。

レビューだけ行ってください。

以下を指摘してください。

SOLID

DDD

Security

OIDC準拠

Cognito互換性

保守性

性能

テスト性

Kubernetes

改善点

100点満点で採点してください。

修正すべき箇所だけ一覧化してください。
```

---

# さらに私はもう一段やります

最後にこれを投げます。

```text
ここまでの成果物を

「OSSとしてGitHubへ公開できる品質」

を100点としてレビューしてください。

以下の観点で改善してください。

設計

命名

コード品質

TypeScript

Prisma

OIDC準拠

Express

Security

Docker

Kubernetes

README

CI/CD

GitHub Actions

テスト

ライセンス

Issueテンプレート

PullRequestテンプレート

改善案を提示してください。
```

---

## これが一番効くプロンプト

実は最後に私は必ずこれを投げます。

```text
あなたはGoogleのStaff Engineerです。

この実装を3年後に保守するとしたら、
絶対に今直しておくべき設計上の問題を厳しくレビューしてください。

遠慮はいりません。

コードを書き直さず、
設計上の問題だけを列挙してください。
```

これをやると、LLMは「作るモード」から「レビューするモード」に切り替わり、責務分離の甘さや設定の持ち方、拡張性、セキュリティなど、実装時には見落としがちな点を指摘してくれることが多いです。

---

## 私ならさらに追加する要求

今回の用途なら、**Cognitoへの将来置き換えが最重要要件**なので、各プロンプトの冒頭に次の一文を毎回入れます。

```text
最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。

OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。

設計・実装・レビューのすべてで、この要件を最優先にしてください。
```

この一文を一貫して与えるだけで、LLMは設定の外部化、OIDC標準への準拠、責務分離を意識した提案をしやすくなります。

