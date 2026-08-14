import type { Response } from "express";
import { z } from "zod";
import * as webhooksService from "./webhooks.service.js";
import { SUPPORTED_EVENT_TYPES } from "./webhooks.service.js";
import type { AuthenticatedRequest } from "../auth/admin-auth.middleware.js";
import { asyncHandler } from "../infra/http/async-handler.js";
import { ApiError } from "../infra/http/problem-json.js";
import { createHmac } from "node:crypto";
import { assertSafeWebhookUrl, UnsafeWebhookUrlError } from "../shared/url-safety.js";

// ----------------------------------------------------------------------------
// POST   /api/v1/webhooks
// GET    /api/v1/webhooks
// GET    /api/v1/webhooks/:id
// PATCH  /api/v1/webhooks/:id
// DELETE /api/v1/webhooks/:id
// POST   /api/v1/webhooks/:id/test
// GET    /api/v1/webhooks/:id/logs
// ----------------------------------------------------------------------------

const eventTypeEnum = z.enum(SUPPORTED_EVENT_TYPES);

export const createWebhookBodySchema = z.object({
  targetUrl: z.string().url().max(2048),
  eventTypes: z.array(eventTypeEnum).min(1),
  secret: z.string().min(16).optional(),
  active: z.boolean().optional(),
});

export const updateWebhookBodySchema = z.object({
  targetUrl: z.string().url().max(2048).optional(),
  eventTypes: z.array(eventTypeEnum).min(1).optional(),
  active: z.boolean().optional(),
});

export const listWebhooksQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

export const listWebhookLogsQuerySchema = z.object({
  status: z.enum(["PENDING", "SUCCESS", "FAILED", "RETRYING"]).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().uuid().optional(),
});

function toWebhookResponse(row: {
  id: string;
  targetUrl: string;
  eventTypes: string;
  active: boolean;
  createdAt: Date;
}) {
  return {
    id: row.id,
    targetUrl: row.targetUrl,
    eventTypes: JSON.parse(row.eventTypes),
    active: row.active,
    createdAt: row.createdAt.toISOString(),
  };
}

export const createWebhookHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const row = await webhooksService.createWebhookSubscription(req.body);
  res.status(201).location(`/api/v1/webhooks/${row.id}`).json(toWebhookResponse(row));
});

export const listWebhooksHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const query = (req as unknown as { validatedQuery: z.infer<typeof listWebhooksQuerySchema> }).validatedQuery;
  const { items, nextCursor } = await webhooksService.listWebhookSubscriptions(query);
  res.status(200).json({ items: items.map(toWebhookResponse), nextCursor });
});

export const getWebhookHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const row = await webhooksService.getWebhookSubscription(req.params.id);
  res.status(200).json(toWebhookResponse(row));
});

export const updateWebhookHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const row = await webhooksService.updateWebhookSubscription(req.params.id, req.body);
  res.status(200).json(toWebhookResponse(row));
});

export const deleteWebhookHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  await webhooksService.deleteWebhookSubscription(req.params.id);
  res.status(204).send();
});

export const testWebhookHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const row = await webhooksService.getWebhookSubscription(req.params.id);

  try {
    await assertSafeWebhookUrl(row.targetUrl);
  } catch (err) {
    if (err instanceof UnsafeWebhookUrlError) {
      throw new ApiError(422, "unsafe-target-url", err.message);
    }
    throw err;
  }

  const body = JSON.stringify({
    eventType: "webhook.test",
    payload: { message: "This is a test delivery." },
    deliveredAt: new Date().toISOString(),
  });
  const signature = createHmac("sha256", row.secret).update(body).digest("hex");

  const startedAt = Date.now();
  try {
    const response = await fetch(row.targetUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Webhook-Signature": signature },
      body,
    });
    res.status(200).json({
      delivered: response.ok,
      httpStatusCode: response.status,
      latencyMs: Date.now() - startedAt,
    });
  } catch {
    throw new ApiError(502, "delivery-failed", "Failed to deliver test webhook to target URL.");
  }
});

export const listWebhookLogsHandler = asyncHandler(async (req: AuthenticatedRequest, res: Response) => {
  const query = (req as unknown as { validatedQuery: z.infer<typeof listWebhookLogsQuerySchema> }).validatedQuery;
  const { items, nextCursor } = await webhooksService.listWebhookLogs(req.params.id, query);
  res.status(200).json({
    items: items.map((log) => ({
      id: log.id,
      eventType: log.eventType,
      status: log.status,
      httpStatusCode: log.httpStatusCode,
      attemptCount: log.attemptCount,
      lastAttemptAt: log.lastAttemptAt?.toISOString() ?? null,
      createdAt: log.createdAt.toISOString(),
    })),
    nextCursor,
  });
});
