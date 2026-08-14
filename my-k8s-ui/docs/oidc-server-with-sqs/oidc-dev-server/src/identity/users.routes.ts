import { Router } from "express";
import { requireAdminAuth } from "../auth/admin-auth.middleware.js";
import { validateBody, validateQuery } from "../middleware/validation.js";
import {
  createUserHandler,
  createUserBodySchema,
  listUsersHandler,
  listUsersQuerySchema,
  getUserHandler,
  updateUserHandler,
  updateUserBodySchema,
  deleteUserHandler,
  enableUserHandler,
  disableUserHandler,
} from "./users.controller.js";
import { listUserGroupsHandler, addUserToGroupHandler, removeUserFromGroupHandler } from "./groups.controller.js";

// ----------------------------------------------------------------------------
// /api/v1/users 配下のルーティング。すべて管理者認証必須。
// ----------------------------------------------------------------------------

export const usersRouter = Router();

usersRouter.use(requireAdminAuth);

usersRouter.post("/users", validateBody(createUserBodySchema), createUserHandler);
usersRouter.get("/users", validateQuery(listUsersQuerySchema), listUsersHandler);
usersRouter.get("/users/:userId", getUserHandler);
usersRouter.patch("/users/:userId", validateBody(updateUserBodySchema), updateUserHandler);
usersRouter.delete("/users/:userId", deleteUserHandler);

usersRouter.post("/users/:userId/enable", enableUserHandler);
usersRouter.post("/users/:userId/disable", disableUserHandler);

usersRouter.get("/users/:userId/groups", listUserGroupsHandler);
usersRouter.post("/users/:userId/groups/:groupId", addUserToGroupHandler);
usersRouter.delete("/users/:userId/groups/:groupId", removeUserFromGroupHandler);
