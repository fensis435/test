import { Router } from "express";
import { requireAdminAuth } from "../auth/admin-auth.middleware.js";
import { validateBody, validateQuery } from "../middleware/validation.js";
import {
  createClientHandler,
  createClientBodySchema,
  listClientsHandler,
  listClientsQuerySchema,
  getClientHandler,
  updateClientHandler,
  updateClientBodySchema,
  deleteClientHandler,
  rotateClientSecretHandler,
} from "./clients.controller.js";

// ----------------------------------------------------------------------------
// /api/v1/clients 配下のルーティング。すべて管理者認証必須。
// ----------------------------------------------------------------------------

export const clientsRouter = Router();

clientsRouter.use(requireAdminAuth);

clientsRouter.post("/clients", validateBody(createClientBodySchema), createClientHandler);
clientsRouter.get("/clients", validateQuery(listClientsQuerySchema), listClientsHandler);
clientsRouter.get("/clients/:clientId", getClientHandler);
clientsRouter.patch("/clients/:clientId", validateBody(updateClientBodySchema), updateClientHandler);
clientsRouter.delete("/clients/:clientId", deleteClientHandler);
clientsRouter.post("/clients/:clientId/secret/rotate", rotateClientSecretHandler);
