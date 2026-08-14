import { createHmac } from "node:crypto";
import { prisma } from "../infra/persistence/prisma-client.js";
import { env } from "../config/env.js";
import { assertSafeWebhookUrl } from "../shared/url-safety.js";

// ----------------------------------------------------------------------------
// Identity/Groups の各サービスから呼ばれるイベント発火口。
// 対象のUser/Group等が将来削除されてもログが監査目的で残るよう、
// WebhookLogテーブルはFKを持たない設計(前回DB設計の意図を踏襲)。
//
// Cognito本番では、この配信の役割はLambdaトリガー(PreSignUp/
// PostConfirmation等の同期呼び出し)に置き換わる。Railsのイベント受信側
// (UserLifecycleEventPort)はHTTPでイベントを受け取るという抽象を保てば、
// 送信元がこのDispatcherかLambda経由かの違いのみで移行できる設計とする。
// ----------------------------------------------------------------------------

export async function dispatchWebhookEvent(eventType: string, payload: Record<string, unknown>): Promise<void> {
  const subscriptions = await prisma.webhookSubscription.findMany({
    where: { active: true, deletedAt: null },
  });

  const targets = subscriptions.filter((sub: (typeof subscriptions)[number]) => {
    const eventTypes = JSON.parse(sub.eventTypes) as string[];
    return eventTypes.includes(eventType);
  });

  for (const sub of targets) {
    const log = await prisma.webhookLog.create({
      data: {
        eventType,
        targetUrl: sub.targetUrl,
        payload: JSON.stringify(payload),
        status: "PENDING",
      },
    });

    // 開発サーバーでは同期的に1回配信を試みる(厳密な非同期キュー実装は不要)。
    await attemptDelivery(log.id, sub.targetUrl, sub.secret, eventType, payload);
  }
}

async function attemptDelivery(
  logId: string,
  targetUrl: string,
  secret: string,
  eventType: string,
  payload: Record<string, unknown>
): Promise<void> {
  // [修正: レビュー指摘#2] 登録時だけでなく配信直前にも検証する。
  // DNSレコードが登録後に変更された場合(DNS Rebinding)への対策。
  try {
    await assertSafeWebhookUrl(targetUrl);
  } catch (err) {
    await prisma.webhookLog.update({
      where: { id: logId },
      data: {
        status: "FAILED",
        attemptCount: { increment: 1 },
        lastAttemptAt: new Date(),
        responseBodySnippet: `Blocked by SSRF guard: ${err instanceof Error ? err.message : "unknown"}`.slice(0, 500),
        nextRetryAt: null,
      },
    });
    return;
  }

  const body = JSON.stringify({ eventType, payload, deliveredAt: new Date().toISOString() });
  const signature = createHmac("sha256", secret).update(body).digest("hex");

  try {
    const response = await fetch(targetUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Signature": signature,
      },
      body,
    });

    const responseText = await response.text().catch(() => "");

    await prisma.webhookLog.update({
      where: { id: logId },
      data: {
        status: response.ok ? "SUCCESS" : "FAILED",
        httpStatusCode: response.status,
        attemptCount: { increment: 1 },
        lastAttemptAt: new Date(),
        responseBodySnippet: responseText.slice(0, 500),
        nextRetryAt: response.ok ? null : computeNextRetry(1),
      },
    });
  } catch (err) {
    await prisma.webhookLog.update({
      where: { id: logId },
      data: {
        status: "RETRYING",
        attemptCount: { increment: 1 },
        lastAttemptAt: new Date(),
        responseBodySnippet: err instanceof Error ? err.message.slice(0, 500) : "unknown error",
        nextRetryAt: computeNextRetry(1),
      },
    });
  }
}

function computeNextRetry(attemptCount: number): Date {
  const delayMs = env.WEBHOOK_RETRY_BASE_DELAY_MS * Math.pow(2, attemptCount - 1);
  return new Date(Date.now() + delayMs);
}

/**
 * リトライ対象(status = RETRYING かつ nextRetryAt が到来済み)を処理する。
 * K8sのCronJob等から定期実行される想定。
 */
export async function processRetryQueue(): Promise<void> {
  const pending = await prisma.webhookLog.findMany({
    where: {
      status: "RETRYING",
      nextRetryAt: { lte: new Date() },
      attemptCount: { lt: env.WEBHOOK_MAX_ATTEMPTS },
    },
    take: 50,
  });

  for (const log of pending) {
    const subscription = await prisma.webhookSubscription.findFirst({
      where: { targetUrl: log.targetUrl, active: true, deletedAt: null },
    });
    if (!subscription) {
      await prisma.webhookLog.update({ where: { id: log.id }, data: { status: "FAILED" } });
      continue;
    }
    await attemptDelivery(log.id, log.targetUrl, subscription.secret, log.eventType, JSON.parse(log.payload));
  }
}
