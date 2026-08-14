import { Router } from "express";
import { requireAdminAuth } from "../auth/admin-auth.middleware.js";
import { validateBody, validateQuery } from "../middleware/validation.js";
import {
  createWebhookHandler,
  createWebhookBodySchema,
  listWebhooksHandler,
  listWebhooksQuerySchema,
  getWebhookHandler,
  updateWebhookHandler,
  updateWebhookBodySchema,
  deleteWebhookHandler,
  testWebhookHandler,
  listWebhookLogsHandler,
  listWebhookLogsQuerySchema,
} from "./webhooks.controller.js";

// ----------------------------------------------------------------------------
// /api/v1/webhooks 配下のルーティング。すべて管理者認証必須。
// ----------------------------------------------------------------------------

export const webhooksRouter = Router();

webhooksRouter.use(requireAdminAuth);

webhooksRouter.post("/webhooks", validateBody(createWebhookBodySchema), createWebhookHandler);
webhooksRouter.get("/webhooks", validateQuery(listWebhooksQuerySchema), listWebhooksHandler);
webhooksRouter.get("/webhooks/:id", getWebhookHandler);
webhooksRouter.patch("/webhooks/:id", validateBody(updateWebhookBodySchema), updateWebhookHandler);
webhooksRouter.delete("/webhooks/:id", deleteWebhookHandler);
webhooksRouter.post("/webhooks/:id/test", testWebhookHandler);
webhooksRouter.get("/webhooks/:id/logs", validateQuery(listWebhookLogsQuerySchema), listWebhookLogsHandler);
