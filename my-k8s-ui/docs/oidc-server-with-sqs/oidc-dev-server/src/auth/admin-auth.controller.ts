import type { Request, Response } from "express";
import argon2 from "argon2";
import { SignJWT, decodeJwt } from "jose";
import { z } from "zod";
import { prisma } from "../infra/persistence/prisma-client.js";
import { env } from "../config/env.js";
import { ApiError } from "../infra/http/problem-json.js";
import type { AuthenticatedRequest } from "./admin-auth.middleware.js";
import { revokeToken, purgeExpiredRevocations } from "./admin-token-store.js";

// ----------------------------------------------------------------------------
// 人間の管理者がManagement APIツールから使うログイン/ログアウト。
// 前回確認済み: サービス間認証ではなく人間の管理者利用が想定。
// Cognito本番には対応物が存在しないため、この機能は移行時に廃止される
// 前提で設計する(README/ADR記載)。
//
// [修正: レビュー指摘#1] logout()がDB永続化された失効ストアに書き込むよう変更。
// ----------------------------------------------------------------------------

export const loginBodySchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const secretKey = new TextEncoder().encode(env.ADMIN_JWT_SECRET);

export async function login(req: Request, res: Response): Promise<void> {
  const { email, password } = req.body as z.infer<typeof loginBodySchema>;
  const normalizedEmail = email.trim().toLowerCase();

  const adminUser = await prisma.adminUser.findFirst({
    where: { email: normalizedEmail, deletedAt: null },
  });

  // ユーザー列挙攻撃対策: 存在しない場合もダミーハッシュ検証を行い応答時間を揃える
  const passwordHashToVerify =
    adminUser?.passwordHash ?? "$argon2id$v=19$m=65536,t=3,p=4$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
  const passwordValid = await argon2.verify(passwordHashToVerify, password).catch(() => false);

  if (!adminUser || !passwordValid) {
    throw new ApiError(401, "invalid-credentials", "Email or password is incorrect.");
  }

  const jti = crypto.randomUUID();
  const accessToken = await new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(adminUser.id)
    .setJti(jti)
    .setIssuedAt()
    .setExpirationTime(`${env.ADMIN_JWT_TTL_SECONDS}s`)
    .sign(secretKey);

  const expiresAt = new Date(Date.now() + env.ADMIN_JWT_TTL_SECONDS * 1000);

  // 日和見的なクリーンアップ(専用バッチを用意しない開発環境向けの簡易対応)
  void purgeExpiredRevocations();

  res.status(200).json({
    sessionId: jti,
    accessToken,
    expiresAt: expiresAt.toISOString(),
  });
}

export async function logout(req: AuthenticatedRequest, res: Response): Promise<void> {
  const authHeader = req.headers.authorization;

  if (authHeader?.startsWith("Bearer ")) {
    const token = authHeader.slice("Bearer ".length);
    try {
      const payload = decodeJwt(token);
      if (payload.jti && payload.exp) {
        await revokeToken(payload.jti, new Date(payload.exp * 1000));
      }
    } catch {
      // requireAdminAuthで既に署名検証済みのため通常到達しないが、
      // 万一デコードに失敗してもログアウト自体は204で成功させる。
    }
  }

  res.status(204).send();
}
