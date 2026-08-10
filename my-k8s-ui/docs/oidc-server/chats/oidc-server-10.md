SQLiteは`enum`型をネイティブサポートしていません(Prisma公式の既知の制約)。schemaを修正します。全体像を把握しました。SQLiteのenum非対応に対応し、String型 + アプリケーション層でのバリデーション(zod)に置き換えます。enum型の定義をTypeScript側に集約する`shared/enums.ts`を新規作成します。`@prisma/client`からenum型をimportしていた3ファイルを修正します。良好です。念のため`status`比較箇所(`"ACTIVE"`等)が引き続き正しく動作するか、TypeScript構文チェックも含め全体を検証します。コメント内の言及のみで、実際の`enum`宣言は残っていません。問題ありません。ZIPを再生成して提供します。# 原因と修正内容

## 原因

**SQLiteはPrismaのネイティブ`enum`をサポートしていません**。これはPrisma公式ドキュメントに明記されているコネクタ制約で、`sqlite`をdatasourceに指定した時点で`enum`ブロックの使用自体が構文エラーになります(PostgreSQL/MySQLでは有効)。

今回のスキーマは`UserStatus`, `ActorType`, `TokenEndpointAuthMethod`, `CodeChallengeMethod`, `WebhookStatus`の5つを`enum`として定義していたため、`migrate dev`実行時にP1012エラーで全滅していました。**これは実装レベルのミスであり、直前の「3年後の保守性」レビューで指摘した`OidcGenericStore`の型安全性欠如の問題ともつながっています**——enumが使えない制約に気づかず場当たり的にString型へ倒すと、今回のように「DBスキーマとアプリケーションコードのどちらが正か」が曖昧になりがちです。

## 修正内容

1. **`prisma/schema.prisma`**: 全`enum`ブロックを削除し、該当フィールドを`String`型(適切な`@default`付き)に変更
2. **`src/shared/enums.ts`を新設**: 許容値のSingle Source of Truthとして、TypeScriptの`as const`配列 + リテラル型union(`UserStatus`, `ActorType`, `TokenEndpointAuthMethod`, `CodeChallengeMethod`, `WebhookStatus`)をここに集約
3. **3ファイルのimport元を修正**: `users.service.ts`, `groups.service.ts`, `clients.service.ts`が`@prisma/client`から直接enum型をimportしていた箇所を`../shared/enums.js`に切り替え

zodバリデーションスキーマ(`z.enum([...])`)は元々コントローラ層で独立定義されていたため、この修正の影響を受けていません。

## 再実行手順

```bash
unzip oidc-dev-server.zip && cd oidc-dev-server
rm -f dev.db  # 前回失敗時に中途半端なファイルが残っていれば削除
npm install
npx prisma generate
npx prisma migrate dev --name init
```

## 補足(直前のレビューとの関連)

直前のStaff Engineerレビューの**指摘2「サードパーティ依存に対する防腐層の欠如」**は、今回のようなコネクタ制約が今後もPrismaやSQLiteのアップデートで顕在化しうることを示唆しています。`src/shared/enums.ts`を今回設けたことは応急処置としては妥当ですが、**「DBスキーマ側はStringだが実際の許容値はTypeScript側にしかない」という二重管理状態**そのものが、3年後には「なぜここにマジックストリングの検証がないのか」という形で技術的負債化する可能性がある点は留意してください。