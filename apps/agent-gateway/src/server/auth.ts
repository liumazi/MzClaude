import type { IncomingMessage } from "node:http";

import type { GatewayConfig } from "../config/config.js";

export const UNAUTHORIZED_MESSAGE = "Missing or invalid launch token.";

export function isHttpRequestAuthorized(
  request: IncomingMessage,
  config: GatewayConfig
): boolean {
  if (!config.security.requireLaunchToken) {
    return true;
  }

  return headerToken(request) === config.authToken;
}

export function isWebSocketRequestAuthorized(
  request: IncomingMessage,
  requestUrl: URL,
  config: GatewayConfig
): boolean {
  if (!config.security.requireLaunchToken) {
    return true;
  }

  return requestUrl.searchParams.get("token") === config.authToken
    || headerToken(request) === config.authToken;
}

function headerToken(request: IncomingMessage): string | undefined {
  const authorization = request.headers.authorization;
  if (authorization?.startsWith("Bearer ")) {
    return authorization.slice("Bearer ".length);
  }

  const explicitToken = request.headers["x-mzclaude-token"];
  return Array.isArray(explicitToken) ? explicitToken[0] : explicitToken;
}
