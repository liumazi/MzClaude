import test from "node:test";
import assert from "node:assert/strict";

import { loadGatewayConfig } from "../src/config/config.js";

test("loadGatewayConfig applies defaults and command line overrides", () => {
  const config = loadGatewayConfig({
    argv: [
      "--host",
      "127.0.0.1",
      "--port",
      "41234",
      "--auth-token",
      "launch-token",
      "--data-dir",
      "C:\\Users\\test\\AppData\\Local\\MzClaude"
    ]
  });

  assert.equal(config.protocolVersion, 1);
  assert.equal(config.host, "127.0.0.1");
  assert.equal(config.port, 41234);
  assert.equal(config.authToken, "launch-token");
  assert.equal(config.dataDir, "C:\\Users\\test\\AppData\\Local\\MzClaude");
  assert.equal(config.security.requireLaunchToken, true);
  assert.equal(config.security.redactSecretsInLogs, true);
});

test("loadGatewayConfig generates a launch token when one is not provided", () => {
  const config = loadGatewayConfig({ argv: ["--port", "0"] });

  assert.equal(config.host, "127.0.0.1");
  assert.equal(config.port, 0);
  assert.match(config.authToken, /^[a-f0-9]{64}$/);
});
