import { PrismaClient } from "@prisma/client";

// ----------------------------------------------------------------------------
// PrismaClientはアプリケーション全体で単一インスタンスを共有する。
// ----------------------------------------------------------------------------

export const prisma = new PrismaClient({
  log: process.env.NODE_ENV === "development" ? ["warn", "error"] : ["error"],
});

export async function disconnectPrisma(): Promise<void> {
  await prisma.$disconnect();
}
