import type { NextFunction, Request, Response } from "express";
import { jwtVerify } from "jose";
import { env } from "../config/env.js";
import { ApiError } from "../infra/http/problem-json.js";
import { isRevoked } from "./admin-token-store.js";

// ----------------------------------------------------------------------------
// Management API(User CRUD / Groups / Webhook等)を保護するための
// 管理者トークン検証ミドルウェア。
// これはエンドユーザー向けOIDCのAccess Tokenとは別の、管理API専用トークン。
//
// [修正: レビュー指摘#1] jtiベースの失効チェック(isRevoked)を追加。
// 署名検証だけでなく、DBに記録された失効済みトークンかどうかを
// 必ず確認するように変更した。
// ----------------------------------------------------------------------------

const secretKey = new TextEncoder().encode(env.ADMIN_JWT_SECRET);

export interface AuthenticatedRequest extends Request {
  adminUserId?: string;
  adminTokenJti?: string;
}

export async function requireAdminAuth(req: AuthenticatedRequest, _res: Response, next: NextFunction): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    next(new ApiError(401, "unauthorized", "Admin access token is required."));
    return;
  }

  const token = authHeader.slice("Bearer ".length);

  try {
    const { payload } = await jwtVerify(token, secretKey, { algorithms: ["HS256"] });

    const jti = payload.jti;
    if (!jti) {
      next(new ApiError(401, "unauthorized", "Admin access token is malformed (missing jti)."));
      return;
    }

    if (await isRevoked(jti)) {
      next(new ApiError(401, "unauthorized", "Admin access token has been revoked."));
      return;
    }

    req.adminUserId = String(payload.sub);
    req.adminTokenJti = jti;
    next();
  } catch {
    next(new ApiError(401, "unauthorized", "Admin access token is invalid or expired."));
  }
}
