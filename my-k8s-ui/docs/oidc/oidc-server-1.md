これは結構大きな成果物になるので、**最初のプロンプトで「完成品」を要求するより、「アーキテクトとして設計させる」→「実装させる」の2段階**にした方が品質が上がります。

私なら以下のようなプロンプトを書きます。

---

# Dev OIDC Server生成プロンプト

```text
あなたはOAuth2/OIDCおよびNode.jsのシニアアーキテクトです。

開発用途専用のOIDC Providerを設計・実装してください。

# 目的

AWS Cognito Hosted UI (Authorization Code + PKCE) を利用するReactアプリケーションの開発環境として利用する。

本番ではAWS Cognitoへ切り替える。

ReactおよびRailsから見ればOIDC Providerとして振る舞えばよい。

Cognitoの完全互換は不要。

目的は

・OIDC認証の開発
・JWT署名検証
・JWKS取得
・Discovery取得
・User CRUD
・ユーザーイベント通知

である。

# 技術要件

Node.js 22 LTS

TypeScript

Express

oidc-provider

SQLite

Prisma

Docker

Kubernetes

# 必須機能

## OIDC

Authorization Code Flow

Authorization Code + PKCE

Discovery

/.well-known/openid-configuration

JWKS

/oauth/token

/oauth/authorize

/logout

/userinfo

ID Token

Access Token

Refresh Token

## Login

シンプルなHTMLログイン画面

username/password認証

セッションCookie

## User管理API

REST API

POST /users

GET /users

GET /users/:id

PATCH /users/:id

DELETE /users/:id

パスワード変更

有効・無効

ロール

グループ

カスタム属性

SQLiteへ保存すること

## Event

ユーザー追加

ユーザー変更

ユーザー削除

有効化

無効化

をJSONイベントとしてWebhookへPOSTする。

Webhook URLは環境変数。

Webhookが未設定なら送信しない。

イベント形式は

{
  "eventType": "...",
  "timestamp": "...",
  "user": {
      ...
  }
}

とする。

## JWT

RSA256

JWKS公開

秘密鍵は起動時生成でもよい。

将来的にファイル保存へ変更しやすい構成。

## Claims

最低限

sub

iss

aud

exp

iat

email

name

groups

role

tenant

をサポート。

tenantはカスタムClaim。

## 管理画面

不要。

REST APIのみ。

## セキュリティ

bcrypt

Helmet

CORS

CSRF考慮

Cookie Secure設定可能

# ディレクトリ構成

以下のようなレイヤード構成

src/

 controllers/

 services/

 repositories/

 models/

 oidc/

 middleware/

 routes/

 prisma/

 views/

# Docker

Dockerfile

docker-compose.yml

Health Check

Non-root User

# Kubernetes

Deployment

Service

Ingress

ConfigMap

Secret

PersistentVolumeClaim

Readiness Probe

Liveness Probe

Resource requests/limits

SecurityContext

NetworkPolicy

を作成。

# Config

環境変数化

PORT

ISSUER

CLIENT_ID

CLIENT_SECRET

DATABASE_URL

WEBHOOK_URL

COOKIE_SECRET

# README

起動方法

OIDC設定方法

React(oidc-client-ts)との接続例

Rails(jwt)との接続例

サンプルcurl

を含める。

# 品質

SOLID

DDDを意識

テスト容易性

型安全

ESLint

Prettier

Vitest

# 出力

以下の順番で出力すること。

1. システム構成図

2. ディレクトリ構成

3. 全体設計

4. DB設計

5. API設計

6. OIDC設定

7. 実装コード

8. Dockerfile

9. docker-compose.yml

10. Kubernetes Manifest

11. README

コードは省略せず全て出力すること。
```

---

## 私ならさらに追加する要求

あなたのシステムに合わせるなら、これも入れます。

```text
本システムはReact(Vite)+Rails API+Kubernetesで動作する。

本OIDC ServerもKubernetesへデプロイする。

Ingress経由で

https://oidc.local.example.com

として公開されることを前提とする。

RailsはJWTを検証するため

/.well-known/openid-configuration

および

JWKS

が取得できること。

Reactはoidc-client-tsを利用する。

本番との差異はIssuerのみになるよう設計すること。
```

---

## さらに品質を上げるコツ

一度に全部作らせるより、私は次の順番で生成させます。

1. **設計レビュー**

   * ディレクトリ構成
   * DB設計
   * OIDCフロー
2. **Node.jsコード生成**
3. **Docker**
4. **Kubernetes**
5. **README**
6. **React接続サンプル**
7. **Rails JWT検証サンプル**

LLMは一度に巨大な成果物を生成すると、途中で整合性が崩れたり、コード品質が落ちたりしがちです。設計を固めてから実装に進める方が、最終的に完成度の高いDev OIDC Serverになりやすいです。

