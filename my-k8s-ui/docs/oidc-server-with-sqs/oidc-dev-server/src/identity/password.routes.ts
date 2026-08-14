import { Router } from "express";
import { requireAdminAuth } from "../auth/admin-auth.middleware.js";
import { validateBody } from "../middleware/validation.js";
import {
  setPasswordHandler,
  setPasswordBodySchema,
  createPasswordResetTokenHandler,
  resetPasswordHandler,
  resetPasswordBodySchema,
} from "./password.controller.js";

// ----------------------------------------------------------------------------
// PUT  /api/v1/users/:userId/password              (管理者認証必須)
// POST /api/v1/users/:userId/password/reset-token  (管理者認証必須)
// POST /api/v1/password/reset                       (ユーザー本人操作、管理者認証不要)
// ----------------------------------------------------------------------------

export const passwordRouter = Router();

passwordRouter.put("/users/:userId/password", requireAdminAuth, validateBody(setPasswordBodySchema), setPasswordHandler);
passwordRouter.post("/users/:userId/password/reset-token", requireAdminAuth, createPasswordResetTokenHandler);

// リセットトークンによる本人操作のため、管理者認証は不要(トークン自体が認可情報)
passwordRouter.post("/password/reset", validateBody(resetPasswordBodySchema), resetPasswordHandler);
