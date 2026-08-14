import type { Response } from "express";
import { z } from "zod";
import * as clientsService from "./clients.service.js";
import type { AuthenticatedRequest } from "../auth/admin-auth.middleware.js";
import { asyncHandler } from "../infra/http/async-handler.js";

// ----------------------------------------------------------------------------
// POST   /api/v1/clients
// GET    /api/v1/clients
// GET    /api/v1/clients/:clientId
// PATCH  /api/v1/clients/:clientId
// DELETE /api/v1/clients/:clientId
// POST   /api/v1/clients/:clientId/secret/rotate
// ----------------------------------------------------------------------------

const SCOPE_ENUM = z.enum(["openid", "email", "profile", "offline_access", "groups"]);
const GRANT_TYPE_ENUM = z.enum(["authorization_code", "refresh_token"]);
const AUTH_METHOD_ENUM = z.enum(["NONE", "CLIENT_SECRET_BASIC", "CLIENT_SECRET_POST"]);

export const createClientBodySchema = z
  .object({
    clientId: z
      .string()
      .min(1)
      .max(128)
      .regex(/^[a-zA-Z0-9._-]+$/, "clientId must be alphanumeric with ._- only"),
    isPublic: z.boolean(),
    tokenEndpointAuthMethod: AUTH_METHOD_ENUM,
    redirectUris: z.array(z.string().url()).min(1),
    postLogoutRedirectUris: z.array(z.string().url()).optional(),
    allowedScopes: z.array(SCOPE_ENUM).min(1),
    grantTypes: z.array(GRANT_TYPE_ENUM).optional(),
  })
  .refine((data) => data.allowedScopes.includes("openid"), {
    message: "allowedScopes must include 'openid'",
    path: ["allowedScopes"],
  });

export const updateClientBodySchema = z.object({
  redirectUris: z.array(z.string().url()).min(1).optional(),
  postLogoutRedirectUris: z.array(z.string().url()).optional(),
  allowedScopes: z.array(SCOPE_ENUM).min(1).optional(),
  grantTypes: z.array(GRANT_TYPE_ENUM).optional(),
});

export const listClientsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

function toClientResponse(client: {
  clientId: string;
  isPublic: boolean;
  tokenEndpointAuthMethod: string;
  redirectUris: string;
  postLogoutRedirectUris: string;
  allowedScopes: string;
  grantTypes: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    clientId: client.clientId,
    isPublic: client.isPublic,
    tokenEndpointAuthMethod: client.tokenEndpointAuthMethod,
    redirectUris: JSON.parse(client.redirectUris),
    postLogoutRedirectUris: JSON.parse(client.postLogoutRedirectUris),
    allowedScopes: JSON.parse(client.allowedScopes),
    grantTypes: JSON.parse(client.grantTypes),
    createdAt: client.createdAt.toISOString(),
    updatedAt: client.updatedAt.toISOString(),
  };
}

export const createClientHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const { client, plainSecret } = await clientsService.createClient(req.body);
  res
    .status(201)
    .location(`/api/v1/clients/${client.clientId}`)
    .json({
      ...toClientResponse(client),
      // 平文シークレットは作成時のみ返却する。以降は取得不可。
      ...(plainSecret ? { clientSecret: plainSecret } : {}),
    });
});

export const listClientsHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const query = (req as unknown as { validatedQuery: z.infer<typeof listClientsQuerySchema> }).validatedQuery;
  const { items, nextCursor } = await clientsService.listClients(query);
  res.status(200).json({ items: items.map(toClientResponse), nextCursor });
});

export const getClientHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const client = await clientsService.getClient(req.params.clientId);
  res.status(200).json(toClientResponse(client));
});

export const updateClientHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const client = await clientsService.updateClient(req.params.clientId, req.body);
  res.status(200).json(toClientResponse(client));
});

export const deleteClientHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  await clientsService.deleteClient(req.params.clientId);
  res.status(204).send();
});

export const rotateClientSecretHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const { plainSecret } = await clientsService.rotateClientSecret(req.params.clientId);
  res.status(200).json({ clientSecret: plainSecret });
});
