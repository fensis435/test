import { SQSClient, SendMessageCommand } from "@aws-sdk/client-sqs";
import { env } from "../config/env.js";
import { buildCognitoStyleEvent } from "../adapters/cognito-compat/cloudtrail-event-builder.js";

// ----------------------------------------------------------------------------
// OIDC-Server -> SQS -> Backend という設計上のイベント発行口。
//
// 本番でCognitoを使う場合、この送信処理自体はAWS側
// (CloudTrail -> EventBridge -> SQS)が代替するため、oidc-dev-serverの
// この実装は本番では一切使われない。開発環境限定の「Cognitoイベント
// パイプラインのシミュレーター」という位置づけ。
//
// SQS_QUEUE_URL が未設定の場合は機能自体を無効化する(Webhookと違い、
// この機能はオプトインの新機能であり、既存のセットアップを壊さないため)。
//
// @aws-sdk/client-sqs は本番のAWS SQSに対してもそのまま使えるSDKであり、
// エンドポイント(SQS_ENDPOINT)を指定するかどうかだけがElasticMQ(開発)と
// 実AWS(将来、本来はCognito側が担うため使わない想定だが念のため)の差異。
// ----------------------------------------------------------------------------

let cachedClient: SQSClient | null = null;

function getClient(): SQSClient {
  if (cachedClient) return cachedClient;

  const hasExplicitCredentials = Boolean(env.AWS_ACCESS_KEY_ID && env.AWS_SECRET_ACCESS_KEY);

  cachedClient = new SQSClient({
    region: env.AWS_REGION,
    // SQS_ENDPOINT未設定なら実AWSのデフォルトエンドポイントを使う
    // (ElasticMQ利用時のみ明示的に上書きする)。
    ...(env.SQS_ENDPOINT ? { endpoint: env.SQS_ENDPOINT } : {}),
    // ElasticMQは署名検証を行わないため、ダミー認証情報で十分。
    // 本番相当(実AWS)ではこれらの環境変数を設定せず、SDKのデフォルト
    // 認証情報プロバイダチェーン(IRSA等)に解決させる。
    ...(hasExplicitCredentials
      ? {
          credentials: {
            accessKeyId: env.AWS_ACCESS_KEY_ID as string,
            secretAccessKey: env.AWS_SECRET_ACCESS_KEY as string,
          },
        }
      : {}),
  });

  return cachedClient;
}

/**
 * ユーザーライフサイクルイベントをCognito CloudTrail形状に変換してSQSへ送信する。
 * fire-and-forget(呼び出し元のAPIレスポンスをブロックしない)。
 * SQS_QUEUE_URLが未設定の場合は何もしない。
 */
export function publishToSqs(eventType: string, payload: Record<string, unknown>): void {
  if (!env.SQS_QUEUE_URL) {
    return;
  }

  const message = buildCognitoStyleEvent(eventType, payload);
  if (!message) {
    // このシステムがまだCognitoイベントとして表現する方法を定義していない
    // 内部イベント種別(例: user.password_resetの一部バリエーション等)。
    // 同期対象外として黙ってスキップする。
    return;
  }

  const command = new SendMessageCommand({
    QueueUrl: env.SQS_QUEUE_URL,
    MessageBody: JSON.stringify(message),
  });

  getClient()
    .send(command)
    .catch((err: unknown) => {
      // eslint-disable-next-line no-console
      console.error(`[sqs-publisher] Failed to publish '${eventType}' event to SQS:`, err);
    });
}
