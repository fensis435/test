import { config as loadDotenv } from "dotenv";
import { z } from "zod";

// ----------------------------------------------------------------------------
// [修正] 従来このファイルは process.env を直接 zod でパースしているだけで、
// .env ファイルを process.env に読み込む処理がどこにも存在しなかった。
// Prisma CLI(`prisma migrate` 等)は独自に .env を自動読込するため
// 気づきにくいが、`tsx` でこのアプリを直接起動する場合は
// dotenv 等で明示的に読み込まない限り process.env に反映されない。
//
// K8s環境では ConfigMap/Secret が envFrom で直接 process.env に注入される
// ため、.env ファイル自体は存在しない。loadDotenv() は対象ファイルが
// 存在しない場合エラーを投げず静かに戻る(戻り値のerrorを無視している)ため、
// この呼び出しはローカル開発・K8s両方の環境で安全に共存できる。
// ----------------------------------------------------------------------------

loadDotenv();

// ----------------------------------------------------------------------------
// 環境変数のバリデーションと型付きアクセスを一元化する。
// OIDC_ISSUER を切り替えるだけで本番Cognito Issuerへの移行が可能な設計。
// ----------------------------------------------------------------------------

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().positive().default(3000),

  OIDC_ISSUER: z.string().url(),
  OIDC_COOKIE_KEYS: z.string().min(1),
  OIDC_JWKS_PATH: z.string().min(1),
  // [追加] リバースプロキシ配下で動作しているかどうか。
  // "true"/"false"の文字列判定にする(z.coerce.boolean()は非空文字列を
  // 全てtrueにしてしまい "false" という文字列すらtrueになる典型的な
  // footgunがあるため、明示的な文字列比較にしている)。
  OIDC_TRUST_PROXY: z
    .enum(["true", "false"])
    .default("false")
    .transform((v) => v === "true"),

  DATABASE_URL: z.string().min(1),

  ADMIN_JWT_SECRET: z.string().min(16),
  ADMIN_JWT_TTL_SECONDS: z.coerce.number().int().positive().default(3600),

  WEBHOOK_MAX_ATTEMPTS: z.coerce.number().int().positive().default(5),
  WEBHOOK_RETRY_BASE_DELAY_MS: z.coerce.number().int().positive().default(2000),

  // [追加] Cognito -> SQS -> Backend 同期パイプラインのシミュレーション用。
  // SQS_QUEUE_URLが未設定なら機能自体が無効化される(オプトイン機能。
  // 既存のセットアップを壊さないための設計)。
  SQS_QUEUE_URL: z.string().url().optional(),
  // ElasticMQ等のSQS互換エンドポイントを使う場合のみ指定する。
  // 未設定なら実AWSのデフォルトエンドポイントが使われる。
  SQS_ENDPOINT: z.string().url().optional(),
  AWS_REGION: z.string().default("ap-northeast-1"),
  // ElasticMQ用のダミー認証情報。実AWS(本来Cognito側が担うため使わない
  // 想定だが念のため)ではこれらを設定せず、SDKのデフォルト認証情報
  // プロバイダチェーン(IRSA等)に解決させること。
  AWS_ACCESS_KEY_ID: z.string().optional(),
  AWS_SECRET_ACCESS_KEY: z.string().optional(),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error("Invalid environment variables:", parsed.error.flatten().fieldErrors);
  // eslint-disable-next-line no-console
  console.error(
    "Hint: if running locally, make sure a '.env' file exists at the project root " +
      "(copy '.env.example' to '.env' and fill in values). See SETUP.md for details."
  );
  throw new Error("Environment variable validation failed. See stderr for details.");
}

export const env = {
  ...parsed.data,
  OIDC_COOKIE_KEYS_ARRAY: parsed.data.OIDC_COOKIE_KEYS.split(",").map((s) => s.trim()),
};
