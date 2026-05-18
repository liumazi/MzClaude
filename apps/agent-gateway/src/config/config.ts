import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type GatewaySecurityConfig = {
  requireLaunchToken: boolean;
  allowRemoteHosts: boolean;
  redactSecretsInLogs: boolean;
};

export type GatewayConfig = {
  protocolVersion: 1;
  version: string;
  host: string;
  port: number;
  authToken: string;
  dataDir?: string;
  security: GatewaySecurityConfig;
};

type LoadGatewayConfigOptions = {
  argv?: string[];
  cwd?: string;
};

type DefaultAgentConfig = {
  protocolVersion: 1;
  gateway: {
    host: string;
    port: number;
  };
  security: GatewaySecurityConfig;
};

export function loadGatewayConfig(options: LoadGatewayConfigOptions = {}): GatewayConfig {
  const cwd = options.cwd ?? process.cwd();
  const argv = options.argv ?? process.argv.slice(2);
  const args = parseArgs(argv);
  const defaults = readJson<DefaultAgentConfig>(
    path.resolve(cwd, "..", "..", "config", "default.agent.json")
  );
  const packageJson = readJson<{ version: string }>(path.resolve(cwd, "package.json"));

  return {
    protocolVersion: defaults.protocolVersion,
    version: packageJson.version,
    host: args.get("host") ?? defaults.gateway.host,
    port: parsePort(args.get("port") ?? String(defaults.gateway.port)),
    authToken: args.get("auth-token") ?? crypto.randomBytes(32).toString("hex"),
    dataDir: args.get("data-dir"),
    security: defaults.security
  };
}

function parseArgs(argv: string[]): Map<string, string> {
  const args = new Map<string, string>();

  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item?.startsWith("--")) {
      continue;
    }

    const name = item.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      args.set(name, "");
      continue;
    }

    args.set(name, value);
    index += 1;
  }

  return args;
}

function parsePort(value: string): number {
  const port = Number(value);
  if (!Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error(`Invalid gateway port: ${value}`);
  }

  return port;
}

function readJson<T>(filePath: string): T {
  return JSON.parse(fs.readFileSync(filePath, "utf8")) as T;
}
