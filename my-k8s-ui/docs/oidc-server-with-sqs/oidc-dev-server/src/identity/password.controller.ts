import type { Response } from "express";
import { randomBytes, createHash } from "node:crypto";
import argon2 from "argon2";
import { z } from "zod";
import { prisma } from "../infra/persistence/prisma-client.js";
import { ApiError } from "../infra/http/problem-json.js";
import { asyncHandler } from "../infra/http/async-handler.js";
import type { AuthenticatedRequest } from "../auth/admin-auth.middleware.js";
import * as usersService from "./users.service.js";
import { publishUserLifecycleEvent } from "../webhooks/event-publisher.js";

// ----------------------------------------------------------------------------
// PUT  /api/v1/users/:userId/password
// POST /api/v1/users/:userId/password/reset-token
// POST /api/v1/password/reset
// ----------------------------------------------------------------------------

export const setPasswordBodySchema = z.object({
  newPassword: z.string().min(8),
  requireChangeOnNextLogin: z.boolean().optional().default(false),
});

export const resetPasswordBodySchema = z.object({
  resetToken: z.string().min(1),
  newPassword: z.string().min(8),
});

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export const setPasswordHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.getUser(req.params.userId);
  const { newPassword } = req.body as z.infer<typeof setPasswordBodySchema>;

  const passwordHash = await argon2.hash(newPassword);

  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash },
  });

  publishUserLifecycleEvent("user.password_set", { userId: user.id });

  res.status(204).send();
});

export const createPasswordResetTokenHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.getUser(req.params.userId);

  const rawToken = randomBytes(32).toString("base64url");
  const tokenHash = sha256(rawToken);
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000); // 30分

  await prisma.passwordResetToken.create({
    data: { tokenHash, userId: user.id, expiresAt },
  });

  res.status(201).json({ resetToken: rawToken, expiresAt: expiresAt.toISOString() });
});

export const resetPasswordHandler = asyncHandler(async (req, res: Response) => {
  const { resetToken, newPassword } = req.body as z.infer<typeof resetPasswordBodySchema>;
  const tokenHash = sha256(resetToken);

  const tokenRow = await prisma.passwordResetToken.findUnique({ where: { tokenHash } });

  if (!tokenRow) {
    throw new ApiError(404, "not-found", "Reset token not found.");
  }
  if (tokenRow.usedAt) {
    throw new ApiError(400, "token-already-used", "Reset token has already been used.", [
      { field: "resetToken", code: "TOKEN_ALREADY_USED", message: "This reset token was already consumed." },
    ]);
  }
  if (tokenRow.expiresAt.getTime() < Date.now()) {
    throw new ApiError(400, "token-expired", "Reset token has expired.", [
      { field: "resetToken", code: "TOKEN_EXPIRED", message: "This reset token has expired." },
    ]);
  }

  const passwordHash = await argon2.hash(newPassword);

  await prisma.$transaction([
    prisma.user.update({ where: { id: tokenRow.userId }, data: { passwordHash } }),
    prisma.passwordResetToken.update({ where: { id: tokenRow.id }, data: { usedAt: new Date() } }),
  ]);

  publishUserLifecycleEvent("user.password_reset", { userId: tokenRow.userId });

  res.status(204).send();
});
