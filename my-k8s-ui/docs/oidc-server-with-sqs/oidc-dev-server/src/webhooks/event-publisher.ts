import { dispatchWebhookEvent } from "./dispatcher.js";
import { publishToSqs } from "./sqs-publisher.js";

// ----------------------------------------------------------------------------
// [修正: レビュー指摘#12] DIP違反の解消
//   従来 users.service.ts / groups.service.ts が webhooks/dispatcher.ts の
//   dispatchWebhookEvent を直接importして呼び出しており、Identity層が
//   Webhook層の具象実装に直接依存していた。
//   本修正で「EventPublisher」という抽象(ポート)を定義し、Identity層は
//   この抽象にのみ依存する形に変更する。テスト時はこのポートを
//   フェイク実装に差し替えることでWebhook配信を伴わないユニットテストが
//   書けるようになる(テスト性の改善にも寄与)。
//
// [修正: レビュー指摘#6] 同期配信によるレイテンシ問題の解消
//   従来 dispatchWebhookEvent を await していたため、Webhook宛先の応答
//   遅延がUser CRUD API自体のレスポンスタイムに直結していた。
//   本修正では publish() を非同期・fire-and-forgetにし、APIリクエストの
//   クリティカルパスからWebhook配信を切り離す。配信自体の成否は
//   WebhookLogテーブルに記録されるため、可観測性は損なわれない。
//
// [追加] Cognito -> SQS -> Backend 同期パイプラインのシミュレーション用に、
// SQSへの発行も同じイベント発火口からファンアウトする。Webhook配信と
// 同じくfire-and-forgetであり、SQS_QUEUE_URL未設定時は何もしない
// (sqs-publisher.ts参照)。
// ----------------------------------------------------------------------------

export interface EventPublisher {
  publish(eventType: string, payload: Record<string, unknown>): void;
}

class FireAndForgetWebhookPublisher implements EventPublisher {
  publish(eventType: string, payload: Record<string, unknown>): void {
    // 意図的にawaitしない。失敗はdispatchWebhookEvent内部で
    // WebhookLogに記録され、リクエストのレスポンスには影響させない。
    void dispatchWebhookEvent(eventType, payload).catch((err: unknown) => {
      // eslint-disable-next-line no-console
      console.error(`[webhook] Failed to dispatch event '${eventType}':`, err);
    });

    // SQS発行も同様にfire-and-forget。内部でエラーハンドリング済み
    // (sqs-publisher.ts の publishToSqs 参照)。
    publishToSqs(eventType, payload);
  }
}

let currentPublisher: EventPublisher = new FireAndForgetWebhookPublisher();

/**
 * Identity/Groups等のサービス層はこの関数からのみイベントを発行する。
 * dispatcher.ts を直接参照しないことで、DIPを満たす。
 */
export function publishUserLifecycleEvent(eventType: string, payload: Record<string, unknown>): void {
  currentPublisher.publish(eventType, payload);
}

/**
 * テスト用の差し替えポイント。
 * 例: setEventPublisher({ publish: vi.fn() }) としてWebhook配信を
 * モックし、users.service のユニットテストをネットワークI/Oなしで書ける。
 */
export function setEventPublisher(publisher: EventPublisher): void {
  currentPublisher = publisher;
}

export function resetEventPublisher(): void {
  currentPublisher = new FireAndForgetWebhookPublisher();
}
