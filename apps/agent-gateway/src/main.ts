import { loadGatewayConfig } from "./config/config.js";
import { createLogger } from "./logging/logger.js";
import { createGatewayServer } from "./server/server.js";
import { SessionStore } from "./sessions/sessionStore.js";

async function main(): Promise<void> {
  const config = loadGatewayConfig();
  const logger = createLogger({
    redactSecrets: config.security.redactSecretsInLogs,
    secrets: [config.authToken],
    write: (line) => process.stderr.write(`${line}\n`)
  });
  const sessionStore = new SessionStore();
  const gateway = createGatewayServer({ config, logger, sessionStore });

  await gateway.start();
  process.stdout.write(`${JSON.stringify({
    protocolVersion: config.protocolVersion,
    status: "ready",
    host: config.host,
    port: gateway.port,
    version: config.version
  })}\n`);

  const shutdown = async () => {
    logger.info("gateway_stopping");
    await gateway.stop();
    process.exit(0);
  };

  process.once("SIGINT", () => {
    void shutdown();
  });
  process.once("SIGTERM", () => {
    void shutdown();
  });
}

main().catch((error: unknown) => {
  process.stderr.write(`${JSON.stringify({
    level: "error",
    event: "gateway_start_failed",
    message: error instanceof Error ? error.message : String(error)
  })}\n`);
  process.exit(1);
});
