import { randomBytes, createHash } from "node:crypto";
import { prisma } from "../infra/persistence/prisma-client.js";
import { ApiError } from "../infra/http/problem-json.js";
import { buildPrismaCursorArgs, toCursorPage } from "../shared/pagination.js";
import type { TokenEndpointAuthMethod } from "../shared/enums.js";

// ----------------------------------------------------------------------------
// OAuth Client(Reactの public client, Railsが将来持つ confidential client等)
// の登録・管理を行う。oidc-provider本体は src/oidc-core/adapter.ts の
// PrismaOidcAdapter を通じてこの clients テーブルを直接参照するため、
// ここで登録した内容がそのまま /authorize, /token の検証対象になる。
//
// 重要: この Client 登録APIおよびシード自体はCognito本番には存在しない
// (Cognito App Clientの登録はAWSコンソール/CFn/Terraform等で行う)。
// したがって本APIはこのManagement API群の他の機能と同様、Rails/運用者側
// からのみ利用され、移行時には利用されなくなる想定である。
// ----------------------------------------------------------------------------

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function generateClientSecret(): string {
  return randomBytes(32).toString("base64url");
}

export interface CreateClientInput {
  clientId: string;
  isPublic: boolean;
  tokenEndpointAuthMethod: "NONE" | "CLIENT_SECRET_BASIC" | "CLIENT_SECRET_POST";
  redirectUris: string[];
  postLogoutRedirectUris?: string[];
  allowedScopes: string[];
  grantTypes?: string[];
}

export interface UpdateClientInput {
  redirectUris?: string[];
  postLogoutRedirectUris?: string[];
  allowedScopes?: string[];
  grantTypes?: string[];
}

export interface ListClientsQuery {
  limit: number;
  cursor?: string;
}

function validateAuthMethodConsistency(isPublic: boolean, method: TokenEndpointAuthMethod | string): void {
  if (isPublic && method !== "NONE") {
    throw new ApiError(
      422,
      "invalid-auth-method",
      "Public clients must use tokenEndpointAuthMethod = NONE (PKCE-based, no client secret).",
      [{ field: "tokenEndpointAuthMethod", code: "INVALID", message: "Public client cannot use a client secret." }]
    );
  }
  if (!isPublic && method === "NONE") {
    throw new ApiError(
      422,
      "invalid-auth-method",
      "Confidential clients must use client_secret_basic or client_secret_post.",
      [{ field: "tokenEndpointAuthMethod", code: "INVALID", message: "Confidential client requires a secret-based auth method." }]
    );
  }
}

/**
 * Client作成。Confidential Clientの場合のみ、平文シークレットを一度だけ返却する
 * (以降はハッシュのみ保持し、平文は二度と取得できない)。
 */
export async function createClient(input: CreateClientInput): Promise<{ client: Awaited<ReturnType<typeof prisma.client.create>>; plainSecret: string | null }> {
  validateAuthMethodConsistency(input.isPublic, input.tokenEndpointAuthMethod);

  const existing = await prisma.client.findUnique({ where: { clientId: input.clientId } });
  if (existing) {
    throw new ApiError(409, "duplicate", "A client with this clientId already exists.", [
      { field: "clientId", code: "DUPLICATE", message: "clientId is already registered." },
    ]);
  }

  if (input.redirectUris.length === 0) {
    throw new ApiError(400, "validation-error", "At least one redirectUri is required.", [
      { field: "redirectUris", code: "REQUIRED", message: "redirectUris must not be empty." },
    ]);
  }

  const plainSecret = input.isPublic ? null : generateClientSecret();

  const client = await prisma.client.create({
    data: {
      clientId: input.clientId,
      clientSecretHash: plainSecret ? sha256(plainSecret) : null,
      isPublic: input.isPublic,
      tokenEndpointAuthMethod: input.tokenEndpointAuthMethod,
      redirectUris: JSON.stringify(input.redirectUris),
      postLogoutRedirectUris: JSON.stringify(input.postLogoutRedirectUris ?? []),
      allowedScopes: JSON.stringify(input.allowedScopes),
      grantTypes: JSON.stringify(input.grantTypes ?? ["authorization_code", "refresh_token"]),
    },
  });

  return { client, plainSecret };
}

export async function listClients(query: ListClientsQuery) {
  const rows = await prisma.client.findMany({
    where: { deletedAt: null },
    ...buildPrismaCursorArgs(query),
    orderBy: { createdAt: "desc" },
  });

  return toCursorPage<(typeof rows)[number]>(rows, query.limit);
}

export async function getClient(clientId: string) {
  const client = await prisma.client.findFirst({ where: { clientId, deletedAt: null } });
  if (!client) {
    throw new ApiError(404, "not-found", "Client not found.");
  }
  return client;
}

export async function updateClient(clientId: string, input: UpdateClientInput) {
  const client = await getClient(clientId);

  if (input.redirectUris && input.redirectUris.length === 0) {
    throw new ApiError(400, "validation-error", "At least one redirectUri is required.", [
      { field: "redirectUris", code: "REQUIRED", message: "redirectUris must not be empty." },
    ]);
  }

  return prisma.client.update({
    where: { id: client.id },
    data: {
      ...(input.redirectUris ? { redirectUris: JSON.stringify(input.redirectUris) } : {}),
      ...(input.postLogoutRedirectUris ? { postLogoutRedirectUris: JSON.stringify(input.postLogoutRedirectUris) } : {}),
      ...(input.allowedScopes ? { allowedScopes: JSON.stringify(input.allowedScopes) } : {}),
      ...(input.grantTypes ? { grantTypes: JSON.stringify(input.grantTypes) } : {}),
    },
  });
}

export async function deleteClient(clientId: string): Promise<void> {
  const client = await getClient(clientId);
  await prisma.client.update({ where: { id: client.id }, data: { deletedAt: new Date() } });
}

/**
 * Confidential Clientのシークレットを再発行する。
 * Public Clientに対して呼び出された場合はエラーとする。
 */
export async function rotateClientSecret(clientId: string): Promise<{ plainSecret: string }> {
  const client = await getClient(clientId);

  if (client.isPublic) {
    throw new ApiError(422, "not-applicable", "Public clients do not have a client secret to rotate.", [
      { field: "clientId", code: "NOT_APPLICABLE", message: "Client is public (PKCE-based, no secret)." },
    ]);
  }

  const plainSecret = generateClientSecret();
  await prisma.client.update({
    where: { id: client.id },
    data: { clientSecretHash: sha256(plainSecret) },
  });

  return { plainSecret };
}
