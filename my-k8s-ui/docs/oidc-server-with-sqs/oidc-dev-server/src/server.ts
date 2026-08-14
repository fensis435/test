import { env } from "./config/env.js";
import { createApp } from "./infra/http/app.js";
import { disconnectPrisma } from "./infra/persistence/prisma-client.js";

// ----------------------------------------------------------------------------
// アプリケーション起動処理。
// ----------------------------------------------------------------------------

async function main(): Promise<void> {
  const { app } = createApp();

  const server = app.listen(env.PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`OIDC dev server listening on port ${env.PORT}`);
    // eslint-disable-next-line no-console
    console.log(`Issuer: ${env.OIDC_ISSUER}`);
  });

  const shutdown = async (signal: string): Promise<void> => {
    // eslint-disable-next-line no-console
    console.log(`Received ${signal}, shutting down gracefully...`);
    server.close(async () => {
      await disconnectPrisma();
      process.exit(0);
    });
  };

  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error("Fatal error during startup:", err);
  process.exit(1);
});
