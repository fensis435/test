import { execSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeAll, afterAll, describe, expect, it, vi } from "vitest";

// ----------------------------------------------------------------------------
// [修正: レビュー指摘#5 / #12]
// 従来 prisma シングルトンへの直接依存とグローバルなWebhook呼び出しにより、
// users.service のユニットテストは事実上不可能だった。
//
// 本テストは以下の2点を実演する:
//   1. EventPublisher の差し替え(setEventPublisher)により、実際の
//      Webhook配信(ネットワークI/O)を伴わずにビジネスロジックのみを検証できる
//      ようになったこと(DIP修正の効果)。
//   2. 実SQLite(一時ファイル)を用いた統合テストパターン。
//      Prismaはコード生成を伴うため完全なモック化よりも、軽量な
//      実DB(一時ファイル)を使う統合テストの方が費用対効果が高いという
//      判断による(過度なモック化は却って保守コストを増やすことがある)。
//
// 実行前提: `npx prisma generate` が完了していること(package.jsonの
// prisma:generate、またはCI上のセットアップステップで実行済みであること)。
// ----------------------------------------------------------------------------

let tmpDir: string;
let dbPath: string;

beforeAll(() => {
  tmpDir = mkdtempSync(join(tmpdir(), "oidc-dev-server-test-"));
  dbPath = join(tmpDir, "test.db");
  process.env.DATABASE_URL = `file:${dbPath}`;

  // テスト用DBにスキーマを反映する(マイグレーション履歴を使わずdb pushで高速化)
  execSync("npx prisma db push --skip-generate --schema=prisma/schema.prisma", {
    stdio: "inherit",
    env: { ...process.env, DATABASE_URL: `file:${dbPath}` },
  });
});

afterAll(() => {
  rmSync(tmpDir, { recursive: true, force: true });
});

describe("users.service", () => {
  it("createUser persists a user and publishes a user.created event without awaiting webhook delivery", async () => {
    // 動的importにより、beforeAllで設定したDATABASE_URLをPrismaClientの
    // 初期化前に確実に反映させる。
    const { setEventPublisher, resetEventPublisher } = await import("../webhooks/event-publisher.js");
    const usersService = await import("./users.service.js");

    const publishSpy = vi.fn();
    setEventPublisher({ publish: publishSpy });

    try {
      const user = await usersService.createUser(
        {
          email: "test-user@example.com",
          temporaryPassword: "correct-horse-battery-staple",
        },
        { type: "ADMIN_USER", id: null }
      );

      expect(user.email).toBe("test-user@example.com");
      expect(user.status).toBe("ACTIVE");

      // Webhook配信はfire-and-forgetのため、publish自体は同期的に呼ばれる
      // (実際のHTTP配信は別途dispatcher.ts内で非同期に行われる)。
      expect(publishSpy).toHaveBeenCalledWith(
        "user.created",
        expect.objectContaining({ email: "test-user@example.com" })
      );
    } finally {
      resetEventPublisher();
    }
  });

  it("createUser rejects duplicate emails with ApiError(409)", async () => {
    const { setEventPublisher, resetEventPublisher } = await import("../webhooks/event-publisher.js");
    const usersService = await import("./users.service.js");
    const { ApiError } = await import("../infra/http/problem-json.js");

    setEventPublisher({ publish: vi.fn() });

    try {
      await usersService.createUser(
        { email: "duplicate@example.com", temporaryPassword: "password123" },
        { type: "ADMIN_USER", id: null }
      );

      await expect(
        usersService.createUser(
          { email: "duplicate@example.com", temporaryPassword: "password123" },
          { type: "ADMIN_USER", id: null }
        )
      ).rejects.toMatchObject({ status: 409 } satisfies Partial<InstanceType<typeof ApiError>>);
    } finally {
      resetEventPublisher();
    }
  });
});
