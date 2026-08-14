import argon2 from "argon2";
import { prisma } from "../infra/persistence/prisma-client.js";
import { ApiError } from "../infra/http/problem-json.js";
import { publishUserLifecycleEvent } from "../webhooks/event-publisher.js";
import { buildPrismaCursorArgs, toCursorPage } from "../shared/pagination.js";
import type { ActorType } from "../shared/enums.js";

// ----------------------------------------------------------------------------
// User CRUD / Password / Enable-Disable / Groups の業務ロジック。
// Management API設計(前回確定)をそのまま実装する。
// ----------------------------------------------------------------------------

export interface CreateUserInput {
  email: string;
  givenName?: string;
  familyName?: string;
  temporaryPassword: string;
  groupIds?: string[];
}

export interface UpdateUserInput {
  givenName?: string;
  familyName?: string;
  email?: string;
}

export interface ListUsersQuery {
  email?: string;
  status?: "ACTIVE" | "DISABLED";
  groupId?: string;
  limit: number;
  cursor?: string;
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export async function createUser(input: CreateUserInput, actor: { type: ActorType; id: string | null }) {
  const normalizedEmail = normalizeEmail(input.email);

  const existing = await prisma.user.findUnique({ where: { normalizedEmail } });
  if (existing) {
    throw new ApiError(409, "duplicate", "A user with this email already exists.", [
      { field: "email", code: "DUPLICATE", message: "Email is already registered." },
    ]);
  }

  if (input.groupIds && input.groupIds.length > 0) {
    const foundGroups = await prisma.group.findMany({
      where: { id: { in: input.groupIds }, deletedAt: null },
    });
    if (foundGroups.length !== input.groupIds.length) {
      throw new ApiError(422, "invalid-group-reference", "One or more groupIds do not exist.");
    }
  }

  const passwordHash = await argon2.hash(input.temporaryPassword);

  const user = await prisma.user.create({
    data: {
      email: input.email,
      normalizedEmail,
      passwordHash,
      givenName: input.givenName,
      familyName: input.familyName,
      createdByType: actor.type,
      createdById: actor.id,
      updatedByType: actor.type,
      updatedById: actor.id,
      userGroups: input.groupIds
        ? {
            create: input.groupIds.map((groupId) => ({
              groupId,
              assignedByType: actor.type,
              assignedById: actor.id,
            })),
          }
        : undefined,
    },
  });

  publishUserLifecycleEvent("user.created", { userId: user.id, email: user.email });

  return user;
}

export async function listUsers(query: ListUsersQuery) {
  const where = {
    deletedAt: null,
    ...(query.email ? { email: { contains: query.email } } : {}),
    ...(query.status ? { status: query.status } : {}),
    ...(query.groupId ? { userGroups: { some: { groupId: query.groupId } } } : {}),
  };

  const users = await prisma.user.findMany({
    where,
    ...buildPrismaCursorArgs(query),
    orderBy: { createdAt: "desc" },
  });

  return toCursorPage<(typeof users)[number]>(users, query.limit);
}

export async function getUser(userId: string) {
  const user = await prisma.user.findFirst({
    where: { id: userId, deletedAt: null },
    include: { userGroups: { include: { group: true } } },
  });
  if (!user) {
    throw new ApiError(404, "not-found", "User not found.");
  }
  return user;
}

export async function updateUser(userId: string, input: UpdateUserInput, actor: { type: ActorType; id: string | null }) {
  const user = await getUser(userId);

  if (input.email) {
    const normalizedEmail = normalizeEmail(input.email);
    const existing = await prisma.user.findUnique({ where: { normalizedEmail } });
    if (existing && existing.id !== userId) {
      throw new ApiError(409, "duplicate", "A user with this email already exists.", [
        { field: "email", code: "DUPLICATE", message: "Email is already registered." },
      ]);
    }
  }

  const updated = await prisma.user.update({
    where: { id: user.id },
    data: {
      ...(input.givenName !== undefined ? { givenName: input.givenName } : {}),
      ...(input.familyName !== undefined ? { familyName: input.familyName } : {}),
      ...(input.email
        ? { email: input.email, normalizedEmail: normalizeEmail(input.email), emailVerified: false }
        : {}),
      updatedByType: actor.type,
      updatedById: actor.id,
    },
  });

  publishUserLifecycleEvent("user.updated", { userId: updated.id });

  return updated;
}

export async function deleteUser(userId: string): Promise<void> {
  const user = await getUser(userId);

  // 有効なトークン/セッションを自動失効させてから論理削除する。
  await prisma.$transaction([
    prisma.refreshToken.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: "USER_DELETED" },
    }),
    prisma.session.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date() },
    }),
    prisma.user.update({
      where: { id: user.id },
      data: {
        deletedAt: new Date(),
        normalizedEmail: `${user.normalizedEmail}.deleted.${Date.now()}`,
      },
    }),
  ]);

  publishUserLifecycleEvent("user.deleted", { userId: user.id });
}

export async function enableUser(userId: string, actor: { type: ActorType; id: string | null }) {
  const user = await getUser(userId);

  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { status: "ACTIVE", updatedByType: actor.type, updatedById: actor.id },
  });

  publishUserLifecycleEvent("user.enabled", { userId: updated.id });

  return updated;
}

export async function disableUser(userId: string, actor: { type: ActorType; id: string | null }) {
  const user = await getUser(userId);

  const [updated] = await prisma.$transaction([
    prisma.user.update({
      where: { id: user.id },
      data: { status: "DISABLED", updatedByType: actor.type, updatedById: actor.id },
    }),
    prisma.refreshToken.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: "USER_DISABLED" },
    }),
    prisma.session.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date() },
    }),
  ]);

  publishUserLifecycleEvent("user.disabled", { userId: updated.id });

  return updated;
}
