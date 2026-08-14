import { randomBytes } from "node:crypto";
import { prisma } from "../infra/persistence/prisma-client.js";
import { ApiError } from "../infra/http/problem-json.js";
import { assertSafeWebhookUrl, UnsafeWebhookUrlError } from "../shared/url-safety.js";
import { buildPrismaCursorArgs, toCursorPage } from "../shared/pagination.js";

// ----------------------------------------------------------------------------
// Webhook Subscription CRUD と手動テスト送信、配信ログ参照。
// 実際の配信(リトライ含む)ロジックは dispatcher.ts に分離する。
// ----------------------------------------------------------------------------

export const SUPPORTED_EVENT_TYPES = [
  "user.created",
  "user.updated",
  "user.deleted",
  "user.enabled",
  "user.disabled",
  "user.password_set",
  "user.password_reset",
  "group.membership.changed",
] as const;

export interface CreateWebhookInput {
  targetUrl: string;
  eventTypes: string[];
  secret?: string;
  active?: boolean;
}

export interface UpdateWebhookInput {
  targetUrl?: string;
  eventTypes?: string[];
  active?: boolean;
}

export interface ListWebhooksQuery {
  limit: number;
  cursor?: string;
}

export interface ListWebhookLogsQuery {
  status?: "PENDING" | "SUCCESS" | "FAILED" | "RETRYING";
  limit: number;
  cursor?: string;
}

export async function createWebhookSubscription(input: CreateWebhookInput) {
  await guardTargetUrl(input.targetUrl);

  const secret = input.secret ?? randomBytes(32).toString("hex");

  return prisma.webhookSubscription.create({
    data: {
      targetUrl: input.targetUrl,
      eventTypes: JSON.stringify(input.eventTypes),
      secret,
      active: input.active ?? true,
    },
  });
}

// [修正: レビュー指摘#2] SSRF対策。UnsafeWebhookUrlErrorをApiError(422)に変換する。
async function guardTargetUrl(targetUrl: string): Promise<void> {
  try {
    await assertSafeWebhookUrl(targetUrl);
  } catch (err) {
    if (err instanceof UnsafeWebhookUrlError) {
      throw new ApiError(422, "unsafe-target-url", err.message, [
        { field: "targetUrl", code: "UNSAFE_TARGET", message: err.message },
      ]);
    }
    throw err;
  }
}

export async function listWebhookSubscriptions(query: ListWebhooksQuery) {
  const rows = await prisma.webhookSubscription.findMany({
    where: { deletedAt: null },
    ...buildPrismaCursorArgs(query),
    orderBy: { createdAt: "desc" },
  });

  return toCursorPage<(typeof rows)[number]>(rows, query.limit);
}

export async function getWebhookSubscription(id: string) {
  const row = await prisma.webhookSubscription.findFirst({ where: { id, deletedAt: null } });
  if (!row) throw new ApiError(404, "not-found", "Webhook subscription not found.");
  return row;
}

export async function updateWebhookSubscription(id: string, input: UpdateWebhookInput) {
  const row = await getWebhookSubscription(id);

  if (input.targetUrl !== undefined) {
    await guardTargetUrl(input.targetUrl);
  }

  return prisma.webhookSubscription.update({
    where: { id: row.id },
    data: {
      ...(input.targetUrl !== undefined ? { targetUrl: input.targetUrl } : {}),
      ...(input.eventTypes !== undefined ? { eventTypes: JSON.stringify(input.eventTypes) } : {}),
      ...(input.active !== undefined ? { active: input.active } : {}),
    },
  });
}

export async function deleteWebhookSubscription(id: string): Promise<void> {
  const row = await getWebhookSubscription(id);
  await prisma.webhookSubscription.update({ where: { id: row.id }, data: { deletedAt: new Date() } });
}

export async function listWebhookLogs(subscriptionId: string, query: ListWebhookLogsQuery) {
  // subscriptionIdはWebhookLogにFKを持たせない設計のため、targetUrlで間接的に絞り込む。
  const subscription = await getWebhookSubscription(subscriptionId);

  const rows = await prisma.webhookLog.findMany({
    where: {
      targetUrl: subscription.targetUrl,
      ...(query.status ? { status: query.status } : {}),
    },
    ...buildPrismaCursorArgs(query),
    orderBy: { createdAt: "desc" },
  });

  return toCursorPage<(typeof rows)[number]>(rows, query.limit);
}
