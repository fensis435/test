import { prisma } from "../infra/persistence/prisma-client.js";
import { ApiError } from "../infra/http/problem-json.js";
import { publishUserLifecycleEvent } from "../webhooks/event-publisher.js";
import { buildPrismaCursorArgs, toCursorPage } from "../shared/pagination.js";
import type { ActorType } from "../shared/enums.js";

// ----------------------------------------------------------------------------
// Groups CRUD および User-Group 所属管理の業務ロジック。
// ----------------------------------------------------------------------------

export interface CreateGroupInput {
  name: string;
  description?: string;
}

export interface UpdateGroupInput {
  name?: string;
  description?: string;
}

export interface ListGroupsQuery {
  limit: number;
  cursor?: string;
}

export async function createGroup(input: CreateGroupInput, actor: { type: ActorType; id: string | null }) {
  const existing = await prisma.group.findUnique({ where: { name: input.name } });
  if (existing) {
    throw new ApiError(409, "duplicate", "A group with this name already exists.", [
      { field: "name", code: "DUPLICATE", message: "Group name is already taken." },
    ]);
  }

  return prisma.group.create({
    data: {
      name: input.name,
      description: input.description,
      createdByType: actor.type,
      createdById: actor.id,
      updatedByType: actor.type,
      updatedById: actor.id,
    },
  });
}

export async function listGroups(query: ListGroupsQuery) {
  const groups = await prisma.group.findMany({
    where: { deletedAt: null },
    ...buildPrismaCursorArgs(query),
    orderBy: { createdAt: "desc" },
  });

  return toCursorPage<(typeof groups)[number]>(groups, query.limit);
}

export async function getGroup(groupId: string) {
  const group = await prisma.group.findFirst({ where: { id: groupId, deletedAt: null } });
  if (!group) {
    throw new ApiError(404, "not-found", "Group not found.");
  }
  return group;
}

export async function updateGroup(groupId: string, input: UpdateGroupInput, actor: { type: ActorType; id: string | null }) {
  const group = await getGroup(groupId);

  if (input.name) {
    const existing = await prisma.group.findUnique({ where: { name: input.name } });
    if (existing && existing.id !== groupId) {
      throw new ApiError(409, "duplicate", "A group with this name already exists.", [
        { field: "name", code: "DUPLICATE", message: "Group name is already taken." },
      ]);
    }
  }

  return prisma.group.update({
    where: { id: group.id },
    data: {
      ...(input.name !== undefined ? { name: input.name } : {}),
      ...(input.description !== undefined ? { description: input.description } : {}),
      updatedByType: actor.type,
      updatedById: actor.id,
    },
  });
}

export async function deleteGroup(groupId: string): Promise<void> {
  const group = await getGroup(groupId);
  await prisma.group.update({ where: { id: group.id }, data: { deletedAt: new Date() } });
}

export async function listUserGroups(userId: string) {
  const rows = await prisma.userGroup.findMany({
    where: { userId },
    include: { group: true },
    orderBy: { assignedAt: "desc" },
  });
  return rows.map((r: (typeof rows)[number]) => ({ id: r.group.id, name: r.group.name, assignedAt: r.assignedAt }));
}

export async function addUserToGroup(
  userId: string,
  groupId: string,
  actor: { type: ActorType; id: string | null }
): Promise<void> {
  const user = await prisma.user.findFirst({ where: { id: userId, deletedAt: null } });
  if (!user) throw new ApiError(404, "not-found", "User not found.");

  const group = await prisma.group.findFirst({ where: { id: groupId, deletedAt: null } });
  if (!group) throw new ApiError(404, "not-found", "Group not found.");

  const existing = await prisma.userGroup.findUnique({ where: { userId_groupId: { userId, groupId } } });
  if (existing) {
    // 冪等成功として扱う(前回設計方針)
    return;
  }

  await prisma.userGroup.create({
    data: { userId, groupId, assignedByType: actor.type, assignedById: actor.id },
  });

  publishUserLifecycleEvent("group.membership.changed", { userId, groupId, action: "added" });
}

export async function removeUserFromGroup(userId: string, groupId: string): Promise<void> {
  const existing = await prisma.userGroup.findUnique({ where: { userId_groupId: { userId, groupId } } });
  if (!existing) {
    throw new ApiError(404, "not-found", "User is not a member of this group.", [
      { field: "groupId", code: "NOT_MEMBER", message: "User is not a member of this group." },
    ]);
  }

  await prisma.userGroup.delete({ where: { id: existing.id } });

  publishUserLifecycleEvent("group.membership.changed", { userId, groupId, action: "removed" });
}
