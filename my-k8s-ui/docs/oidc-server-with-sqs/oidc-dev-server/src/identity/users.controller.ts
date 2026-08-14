import type { Response } from "express";
import { z } from "zod";
import * as usersService from "./users.service.js";
import type { AuthenticatedRequest } from "../auth/admin-auth.middleware.js";
import { asyncHandler } from "../infra/http/async-handler.js";

// ----------------------------------------------------------------------------
// POST   /api/v1/users
// GET    /api/v1/users
// GET    /api/v1/users/:userId
// PATCH  /api/v1/users/:userId
// DELETE /api/v1/users/:userId
// ----------------------------------------------------------------------------

export const createUserBodySchema = z.object({
  email: z.string().email().max(254),
  givenName: z.string().max(100).optional(),
  familyName: z.string().max(100).optional(),
  temporaryPassword: z.string().min(8),
  groupIds: z.array(z.string().uuid()).optional(),
});

export const updateUserBodySchema = z.object({
  givenName: z.string().max(100).optional(),
  familyName: z.string().max(100).optional(),
  email: z.string().email().max(254).optional(),
});

export const listUsersQuerySchema = z.object({
  email: z.string().optional(),
  status: z.enum(["ACTIVE", "DISABLED"]).optional(),
  groupId: z.string().uuid().optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

function toUserResponse(user: {
  id: string;
  email: string;
  emailVerified: boolean;
  givenName: string | null;
  familyName: string | null;
  status: string;
  createdAt: Date;
  updatedAt: Date;
  userGroups?: { group: { id: string; name: string } }[];
}) {
  return {
    id: user.id,
    email: user.email,
    emailVerified: user.emailVerified,
    givenName: user.givenName,
    familyName: user.familyName,
    status: user.status,
    ...(user.userGroups ? { groups: user.userGroups.map((ug) => ({ id: ug.group.id, name: ug.group.name })) } : {}),
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}

export const createUserHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.createUser(req.body, { type: "ADMIN_USER", id: req.adminUserId ?? null });
  res.status(201).location(`/api/v1/users/${user.id}`).json(toUserResponse(user));
});

export const listUsersHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const query = (req as unknown as { validatedQuery: z.infer<typeof listUsersQuerySchema> }).validatedQuery;
  const { items, nextCursor } = await usersService.listUsers(query);
  res.status(200).json({ items: items.map((u) => toUserResponse(u)), nextCursor });
});

export const getUserHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.getUser(req.params.userId);
  res.status(200).json(toUserResponse(user));
});

export const updateUserHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.updateUser(req.params.userId, req.body, {
    type: "ADMIN_USER",
    id: req.adminUserId ?? null,
  });
  res.status(200).json(toUserResponse(user));
});

export const deleteUserHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  await usersService.deleteUser(req.params.userId);
  res.status(204).send();
});

export const enableUserHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.enableUser(req.params.userId, { type: "ADMIN_USER", id: req.adminUserId ?? null });
  res.status(200).json({ id: user.id, status: user.status });
});

export const disableUserHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const user = await usersService.disableUser(req.params.userId, { type: "ADMIN_USER", id: req.adminUserId ?? null });
  res.status(200).json({ id: user.id, status: user.status });
});
