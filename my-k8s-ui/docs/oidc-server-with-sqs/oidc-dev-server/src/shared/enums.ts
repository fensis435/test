// ----------------------------------------------------------------------------
// [修正] SQLiteコネクタはPrismaのネイティブenumをサポートしないため
// (`npx prisma migrate dev` 実行時に P1012 エラーとなる)、
// schema.prisma側の該当フィールドはすべて String 型に変更した。
//
// 代わりに、許容値の Single Source of Truth をこのファイルに置く。
// DBスキーマとアプリケーションコードの両方が、常にここで定義した
// リテラル型・配列を参照すること。
//
// PostgreSQL等のenum対応コネクタへ将来移行する場合は、この配列を
// そのままschema.prismaのenumブロックに変換できる。
// ----------------------------------------------------------------------------

export const USER_STATUS_VALUES = ["ACTIVE", "DISABLED"] as const;
export type UserStatus = (typeof USER_STATUS_VALUES)[number];

export const ACTOR_TYPE_VALUES = ["SYSTEM", "ADMIN_USER", "API_CLIENT"] as const;
export type ActorType = (typeof ACTOR_TYPE_VALUES)[number];

export const TOKEN_ENDPOINT_AUTH_METHOD_VALUES = ["NONE", "CLIENT_SECRET_BASIC", "CLIENT_SECRET_POST"] as const;
export type TokenEndpointAuthMethod = (typeof TOKEN_ENDPOINT_AUTH_METHOD_VALUES)[number];

export const CODE_CHALLENGE_METHOD_VALUES = ["S256"] as const;
export type CodeChallengeMethod = (typeof CODE_CHALLENGE_METHOD_VALUES)[number];

export const WEBHOOK_STATUS_VALUES = ["PENDING", "SUCCESS", "FAILED", "RETRYING"] as const;
export type WebhookStatus = (typeof WEBHOOK_STATUS_VALUES)[number];
