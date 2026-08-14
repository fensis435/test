import { PrismaClient } from "@prisma/client";
import argon2 from "argon2";
import { randomBytes, createHash } from "node:crypto";

// ----------------------------------------------------------------------------
// 開発環境の初期データ投入スクリプト。
//   1. React(Vite)用 Public Client(PKCE, client_secretなし)
//   2. 管理者アカウント(AdminUser: Management API /api/v1/* の認証専用)
//   3. テスト用エンドユーザー(User: ブラウザのOIDCログイン画面
//      /interaction/:uid/login で使うアカウント。AdminUserとは別物)
//
// 実行方法:
//   DATABASE_URL=file:./dev.db npx tsx prisma/seed.ts
//   または npm run prisma:seed (package.jsonにprisma.seed設定済み)
//
// 環境変数で値を上書き可能。CI/CDでの再現可能なシードを想定し、
// ハードコードされた秘密情報は含めない。
// ----------------------------------------------------------------------------

const prisma = new PrismaClient();

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

async function seedReactPublicClient(): Promise<void> {
  const clientId = process.env.SEED_REACT_CLIENT_ID ?? "react-dev-client";
  const redirectUris = (process.env.SEED_REACT_REDIRECT_URIS ?? "http://localhost:5173/callback").split(",");
  const postLogoutRedirectUris = (process.env.SEED_REACT_POST_LOGOUT_REDIRECT_URIS ?? "http://localhost:5173/").split(",");

  const existing = await prisma.client.findUnique({ where: { clientId } });
  if (existing) {
    console.log(`[seed] Client '${clientId}' already exists. Skipping.`);
    return;
  }

  await prisma.client.create({
    data: {
      clientId,
      clientSecretHash: null,
      isPublic: true,
      tokenEndpointAuthMethod: "NONE",
      redirectUris: JSON.stringify(redirectUris),
      postLogoutRedirectUris: JSON.stringify(postLogoutRedirectUris),
      allowedScopes: JSON.stringify(["openid", "email", "profile", "offline_access", "groups"]),
      grantTypes: JSON.stringify(["authorization_code", "refresh_token"]),
    },
  });

  console.log(`[seed] Created public client '${clientId}' (redirectUris: ${redirectUris.join(", ")})`);
}

async function seedConfidentialExampleClient(): Promise<void> {
  // Rails等、confidential clientが将来必要になった場合の参考例。
  // デフォルトでは投入しない(SEED_CREATE_CONFIDENTIAL_EXAMPLE=trueの場合のみ)。
  if (process.env.SEED_CREATE_CONFIDENTIAL_EXAMPLE !== "true") {
    return;
  }

  const clientId = "rails-confidential-example";
  const existing = await prisma.client.findUnique({ where: { clientId } });
  if (existing) {
    console.log(`[seed] Client '${clientId}' already exists. Skipping.`);
    return;
  }

  const plainSecret = randomBytes(32).toString("base64url");

  await prisma.client.create({
    data: {
      clientId,
      clientSecretHash: sha256(plainSecret),
      isPublic: false,
      tokenEndpointAuthMethod: "CLIENT_SECRET_BASIC",
      redirectUris: JSON.stringify(["http://localhost:3001/callback"]),
      postLogoutRedirectUris: JSON.stringify([]),
      allowedScopes: JSON.stringify(["openid", "email", "profile"]),
      grantTypes: JSON.stringify(["authorization_code", "refresh_token"]),
    },
  });

  console.log(`[seed] Created confidential client '${clientId}'.`);
  console.log(`[seed] client_secret (displayed once): ${plainSecret}`);
}

async function seedAdminUser(): Promise<void> {
  const email = (process.env.SEED_ADMIN_EMAIL ?? "admin@example.com").toLowerCase();
  const password = process.env.SEED_ADMIN_PASSWORD;

  if (!password) {
    console.log("[seed] SEED_ADMIN_PASSWORD not set. Skipping admin user seed.");
    return;
  }

  const existing = await prisma.adminUser.findUnique({ where: { email } });
  if (existing) {
    console.log(`[seed] Admin user '${email}' already exists. Skipping.`);
    return;
  }

  const passwordHash = await argon2.hash(password);

  await prisma.adminUser.create({
    data: { email, passwordHash },
  });

  console.log(`[seed] Created admin user '${email}'.`);
}

// ----------------------------------------------------------------------------
// [追加] AdminUser(Management API用)とUser(ブラウザOIDCログイン用)は
// 完全に別のテーブル・別の認証経路である(前者は/api/v1/auth/login、
// 後者は/interaction/:uid/loginのブラウザログイン画面)。
// この区別が分かりにくく、AdminUserの認証情報でブラウザログインを試みて
// 「認証に失敗しました」に遭遇するケースがあったため、動作確認用の
// エンドユーザーもここで作成できるようにする。
// ----------------------------------------------------------------------------
async function seedTestEndUser(): Promise<void> {
  const email = (process.env.SEED_TEST_USER_EMAIL ?? "testuser@example.com").toLowerCase();
  const password = process.env.SEED_TEST_USER_PASSWORD;

  if (!password) {
    console.log("[seed] SEED_TEST_USER_PASSWORD not set. Skipping test end-user seed.");
    console.log("[seed] (This is the account used to log in via the browser OIDC login screen ");
    console.log("[seed]  from React — it is NOT the same as the AdminUser used for the Management API.)");
    return;
  }

  const existing = await prisma.user.findUnique({ where: { normalizedEmail: email } });
  if (existing) {
    console.log(`[seed] Test end-user '${email}' already exists. Skipping.`);
    return;
  }

  const passwordHash = await argon2.hash(password);

  await prisma.user.create({
    data: {
      email,
      normalizedEmail: email,
      emailVerified: true,
      passwordHash,
      status: "ACTIVE",
      givenName: "Test",
      familyName: "User",
    },
  });

  console.log(`[seed] Created test end-user '${email}' (for browser OIDC login, not the Management API).`);
}

async function main(): Promise<void> {
  await seedReactPublicClient();
  await seedConfidentialExampleClient();
  await seedAdminUser();
  await seedTestEndUser();
}

main()
  .catch((err) => {
    console.error("[seed] Failed:", err);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
