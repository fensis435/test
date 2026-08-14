import { Router } from "express";
import { validateBody } from "../middleware/validation.js";
import { login, logout, loginBodySchema } from "./admin-auth.controller.js";
import { requireAdminAuth } from "./admin-auth.middleware.js";
import { asyncHandler } from "../infra/http/async-handler.js";

// ----------------------------------------------------------------------------
// POST /api/v1/auth/login
// POST /api/v1/auth/logout
// ----------------------------------------------------------------------------

export const adminAuthRouter = Router();

adminAuthRouter.post("/auth/login", validateBody(loginBodySchema), asyncHandler(login));
adminAuthRouter.post("/auth/logout", requireAdminAuth, asyncHandler(logout));
