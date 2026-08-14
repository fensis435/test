import type { Response } from "express";
import { z } from "zod";
import * as groupsService from "./groups.service.js";
import type { AuthenticatedRequest } from "../auth/admin-auth.middleware.js";
import { asyncHandler } from "../infra/http/async-handler.js";

// ----------------------------------------------------------------------------
// POST   /api/v1/groups
// GET    /api/v1/groups
// GET    /api/v1/groups/:groupId
// PATCH  /api/v1/groups/:groupId
// DELETE /api/v1/groups/:groupId
// GET    /api/v1/users/:userId/groups
// POST   /api/v1/users/:userId/groups/:groupId
// DELETE /api/v1/users/:userId/groups/:groupId
// ----------------------------------------------------------------------------

export const createGroupBodySchema = z.object({
  name: z.string().max(128).min(1),
  description: z.string().max(500).optional(),
});

export const updateGroupBodySchema = z.object({
  name: z.string().max(128).min(1).optional(),
  description: z.string().max(500).optional(),
});

export const listGroupsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

function toGroupResponse(group: { id: string; name: string; description: string | null; createdAt: Date; updatedAt: Date }) {
  return {
    id: group.id,
    name: group.name,
    description: group.description,
    createdAt: group.createdAt.toISOString(),
    updatedAt: group.updatedAt.toISOString(),
  };
}

export const createGroupHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const group = await groupsService.createGroup(req.body, { type: "ADMIN_USER", id: req.adminUserId ?? null });
  res.status(201).location(`/api/v1/groups/${group.id}`).json(toGroupResponse(group));
});

export const listGroupsHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const query = (req as unknown as { validatedQuery: z.infer<typeof listGroupsQuerySchema> }).validatedQuery;
  const { items, nextCursor } = await groupsService.listGroups(query);
  res.status(200).json({ items: items.map(toGroupResponse), nextCursor });
});

export const getGroupHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const group = await groupsService.getGroup(req.params.groupId);
  res.status(200).json(toGroupResponse(group));
});

export const updateGroupHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const group = await groupsService.updateGroup(req.params.groupId, req.body, {
    type: "ADMIN_USER",
    id: req.adminUserId ?? null,
  });
  res.status(200).json(toGroupResponse(group));
});

export const deleteGroupHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  await groupsService.deleteGroup(req.params.groupId);
  res.status(204).send();
});

export const listUserGroupsHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const items = await groupsService.listUserGroups(req.params.userId);
  res.status(200).json({ items });
});

export const addUserToGroupHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  await groupsService.addUserToGroup(req.params.userId, req.params.groupId, {
    type: "ADMIN_USER",
    id: req.adminUserId ?? null,
  });
  res.status(204).send();
});

export const removeUserFromGroupHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  await groupsService.removeUserFromGroup(req.params.userId, req.params.groupId);
  res.status(204).send();
});
