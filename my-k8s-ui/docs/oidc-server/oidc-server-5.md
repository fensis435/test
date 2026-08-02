最優先要件は「AWS Cognito Hosted UIへの置き換え時に、ReactおよびRailsのコード変更を最小化すること」です。
OIDC Providerの実装はCognitoに依存しない標準OIDC準拠とし、Cognito固有機能への依存はアダプタ層に限定してください。
設計・実装・レビューのすべてで、この要件を最優先にしてください。
---
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

---
---

Continuing with the Identity module (Users, Password, Groups):Continuing with the Webhooks module:Now the Express app assembly and server entrypoint:Now the Kubernetes manifests:Prisma schemaが正しくパースできるか検証します。良かったです。全27ファイル + 設定ファイル一式が揃いました。tsconfig.jsonも確認済みです。プロジェクト一式をZIPにまとめて提供します。# 実装完了

これまでの設計(システム構成/ディレクトリ構成/DB設計/REST API設計/OIDC Provider設計)を仕様変更せずすべて反映した、Node.js 22 + TypeScript + Express + oidc-provider + Prisma + SQLiteの実装一式です。ディレクトリ・ファイル単位の全体像は上記の通りで、コードは省略していません。

## 実装上の補足(設計からの逸脱がない箇所の技術的注記)

1. **`OidcGenericStore`テーブルを追加しました**。前回のDB設計8テーブルはそのまま維持していますが、oidc-provider内部が要求するモデル(Interaction, Grant, DeviceCode等)は業務要件の設計対象外だったため、これらの永続化専用に汎用KVテーブルを1つ追加しています。`Client`/`AuthorizationCode`/`RefreshToken`は指示通り業務テーブルへ直接マッピングしています(`src/oidc-core/adapter.ts`)。
2. **`AdminUser`テーブルを追加しました**。管理者ログイン(`/api/v1/auth/login`)はエンドユーザー(`Users`テーブル)とは別主体のため、前回のDB設計で明示的に定義されていなかったこのテーブルを新設しています。
3. **`PasswordResetToken`テーブルを追加しました**。Password APIの`reset-token`発行/`reset`実行に必要な永続化先として設計しています。

いずれも「既存8テーブルの仕様変更」ではなく、Management API/oidc-provider実装上必要な補完テーブルの追加です。もし「追加ではなく既存テーブル内で完結させたい」というご意向があれば、設計を見直します。

## 動作確認について

ネットワーク制限(`binaries.prisma.sh`が許可ドメイン外)により、この環境では`prisma generate`のエンジンバイナリ取得ができず、実行検証はできませんでした。お手元の環境で以下の手順をお試しください。

```bash
unzip oidc-dev-server.zip && cd oidc-dev-server
npm install
cp .env.example .env   # 値を編集
npx prisma migrate dev --name init
npm run dev
```

## 未実装・要確認事項

- `Client`(OAuth Client)登録のためのシードスクリプト/Management APIは未実装です(前回のAPI設計スコープ外だったため)。開発用ReactクライアントのClient登録は`prisma db seed`等で別途投入する運用を想定しています。必要であれば追加します。
- `interactions.ts`のログイン画面はプレーンHTMLの最小実装です。UI意匠は別途フロントエンド側で用意する前提としています。
