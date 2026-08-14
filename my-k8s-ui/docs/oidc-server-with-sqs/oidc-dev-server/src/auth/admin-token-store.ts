import { prisma } from "../infra/persistence/prisma-client.js";

// ----------------------------------------------------------------------------
// 管理者トークンの失効状態をDBに永続化して管理する。
// [修正: レビュー指摘#1] 従来はモジュール内メモリのSetで管理しており、
// requireAdminAuth側からも一度も参照されていなかったため、ログアウト後の
// トークンが有効期限まで使い続けられる重大な不具合があった。
// 本修正でDB永続化(再起動耐性)+ ミドルウェア側での必須チェックに変更する。
// ----------------------------------------------------------------------------

export async function revokeToken(jti: string, expiresAt: Date): Promise<void> {
  await prisma.adminRevokedToken.upsert({
    where: { jti },
    create: { jti, expiresAt },
    update: { expiresAt },
  });
}

export async function isRevoked(jti: string): Promise<boolean> {
  const row = await prisma.adminRevokedToken.findUnique({ where: { jti } });
  return row !== null;
}

/**
 * 期限切れの失効エントリを掃除する(K8s CronJob等から定期実行、
 * もしくはログアウト処理のたびに日和見的に呼び出す)。
 */
export async function purgeExpiredRevocations(): Promise<void> {
  await prisma.adminRevokedToken.deleteMany({ where: { expiresAt: { lt: new Date() } } });
}
