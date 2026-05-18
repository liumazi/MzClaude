import test from "node:test";
import assert from "node:assert/strict";

import { createLogger } from "../src/logging/logger.js";

test("logger writes structured JSON and redacts configured secrets", () => {
  const writes: string[] = [];
  const logger = createLogger({
    redactSecrets: true,
    secrets: ["launch-token"],
    write: (line: string) => writes.push(line)
  });

  logger.info("health_checked", {
    token: "launch-token",
    url: "ws://127.0.0.1/events?token=launch-token"
  });

  assert.equal(writes.length, 1);
  const entry = JSON.parse(writes[0]) as {
    level: string;
    event: string;
    details: Record<string, string>;
  };

  assert.equal(entry.level, "info");
  assert.equal(entry.event, "health_checked");
  assert.equal(entry.details.token, "[REDACTED]");
  assert.equal(entry.details.url, "ws://127.0.0.1/events?token=[REDACTED]");
});
