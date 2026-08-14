import { Router } from "express";
import { requireAdminAuth } from "../auth/admin-auth.middleware.js";
import { validateBody, validateQuery } from "../middleware/validation.js";
import {
  createGroupHandler,
  createGroupBodySchema,
  listGroupsHandler,
  listGroupsQuerySchema,
  getGroupHandler,
  updateGroupHandler,
  updateGroupBodySchema,
  deleteGroupHandler,
} from "./groups.controller.js";

// ----------------------------------------------------------------------------
// /api/v1/groups 配下のルーティング。すべて管理者認証必須。
// ----------------------------------------------------------------------------

export const groupsRouter = Router();

groupsRouter.use(requireAdminAuth);

groupsRouter.post("/groups", validateBody(createGroupBodySchema), createGroupHandler);
groupsRouter.get("/groups", validateQuery(listGroupsQuerySchema), listGroupsHandler);
groupsRouter.get("/groups/:groupId", getGroupHandler);
groupsRouter.patch("/groups/:groupId", validateBody(updateGroupBodySchema), updateGroupHandler);
groupsRouter.delete("/groups/:groupId", deleteGroupHandler);
