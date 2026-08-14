import { prisma } from "../infra/persistence/prisma-client.js";

// ----------------------------------------------------------------------------
// Claims設計(前回レビュー確定分)をそのまま実装する。
//
// 重要: `groups` クレームはOIDC標準には存在しない拡張だが、
// Cognitoのような `cognito:groups` というベンダープレフィックス付き命名は
// 一切使わない。中立名 `groups` に統一し、Cognito固有命名への変換は
// src/adapters/cognito-compat 側の責務とする(このファイルでは行わない)。
// ----------------------------------------------------------------------------

export const claimsConfig = {
  openid: ["sub"],
  email: ["email", "email_verified"],
  profile: ["given_name", "family_name"],
  // 独自拡張クレーム。中立命名。
  groups: ["groups"],
} as const;

export const scopesSupported = ["openid", "email", "profile", "offline_access", "groups"] as const;

/**
 * oidc-provider の findAccount フック実装。
 * sub(=Users.id)からアカウント情報を解決し、要求されたクレーム集合のみを返す。
 */
export async function findAccount(
  _ctx: unknown,
  sub: string
): Promise<{ accountId: string; claims: (use: string, scope: string) => Promise<Record<string, unknown>> } | undefined> {
  const user = await prisma.user.findFirst({
    where: { id: sub, deletedAt: null },
    include: { userGroups: { include: { group: true } } },
  });

  if (!user || user.status !== "ACTIVE") {
    return undefined;
  }

  return {
    accountId: user.id,
    claims: async (_use: string, scope: string) => {
      const requestedScopes = scope.split(" ");
      const claims: Record<string, unknown> = { sub: user.id };

      if (requestedScopes.includes("email")) {
        claims.email = user.email;
        claims.email_verified = user.emailVerified;
      }
      if (requestedScopes.includes("profile")) {
        claims.given_name = user.givenName ?? null;
        claims.family_name = user.familyName ?? null;
      }
      if (requestedScopes.includes("groups")) {
        claims.groups = user.userGroups.map((ug: (typeof user.userGroups)[number]) => ug.group.name);
      }

      return claims;
    },
  };
}

/**
 * Access Tokenには最小構成のみを含める方針(前回設計確定)。
 * email/profile等のPII的クレームは含めない。
 * 理由: Cognitoのデフォルト設定はAccess TokenにPIIを含まないため、
 * ここで揃えておかないと本番切替時にRailsのAccess Token解析ロジックが
 * 静かに壊れる。
 */
export function extraAccessTokenClaims(): Record<string, unknown> {
  return {};
}
