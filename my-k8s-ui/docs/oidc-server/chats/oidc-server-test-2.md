`--admin-email`と`--admin-password`は、`oidc-dev-server`側の`prisma/seed.ts`で作成される**管理者アカウント(`AdminUser`)**の認証情報です。Management API(`/api/v1/*`)を保護している、エンドユーザー向けOIDC認証とは別物の「管理者ログイン」用アカウントです。

## 該当箇所

`oidc-dev-server`の`prisma/seed.ts`にこの処理があります。

```ruby
async function seedAdminUser(): Promise<void> {
  const email = (process.env.SEED_ADMIN_EMAIL ?? "admin@example.com").toLowerCase();
  const password = process.env.SEED_ADMIN_PASSWORD;
  ...
  await prisma.adminUser.create({ data: { email, passwordHash } });
}
```

`SEED_ADMIN_PASSWORD`が設定されていない場合は、このシードはスキップされ、管理者アカウントは作成されません(READMEにも「password未設定時はスキップ」と明記していました)。

## 設定手順

`oidc-dev-server`側で、シードを実行する際にこの2つの環境変数を渡します。

```bash
cd oidc-dev-server
SEED_ADMIN_EMAIL=admin@example.com SEED_ADMIN_PASSWORD=change-me-please npx prisma db seed
```

このコマンドを実行すると、`AdminUser`テーブルに`admin@example.com` / `change-me-please`(ハッシュ化して保存)というレコードが作られます。

`ruby scripts/register_client.rb --admin-email admin@example.com --admin-password change-me-please`は、この値をそのまま`POST /api/v1/auth/login`に渡してログインし、そのレスポンスの`accessToken`を使って`POST /api/v1/clients`(Reactクライアントの登録)を叩いています。

## つまずきやすい点

1. **`oidc-web-test`側の`.env`や設定ファイルではありません**。`oidc-dev-server`側でシードを実行しない限り、どんなメール/パスワードを指定しても`401 invalid-credentials`になります。
2. `.env`に`SEED_ADMIN_PASSWORD`を書いても、それだけでは反映されません。**`npx prisma db seed`を実行して初めてDBに書き込まれます**。
3. 既にシード済みで別のパスワードにしたい場合、`seedAdminUser()`は「既存なら何もしない」実装のため、パスワードを変更したい場合はDBの`admin_users`テーブルを直接操作するか、Management APIに管理者パスワード変更用のエンドポイントを別途追加する必要があります(現状の設計にはまだありません)。

まず`oidc-dev-server`側で管理者アカウントが実際に作られているか確認したい場合は、以下で直接ログインを試すのが手っ取り早いです。

```bash
curl -i -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"change-me-please"}'
```

200が返ってこなければ、シードがまだ実行されていない可能性が高いです。
