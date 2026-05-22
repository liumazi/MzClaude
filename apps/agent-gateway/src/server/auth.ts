/**
 * 启动令牌鉴权：当 requireLaunchToken 为 true 时，HTTP 与 WebSocket 须携带有效 token。
 */
import type { IncomingMessage } from "node:http";

import type { GatewayConfig } from "../config/config.js";

export const UNAUTHORIZED_MESSAGE = "Missing or invalid launch token.";

/** 校验 HTTP 请求：Authorization Bearer 或 x-mzclaude-token */
export function isHttpRequestAuthorized(
  request: IncomingMessage,
  config: GatewayConfig
): boolean {
  if (!config.security.requireLaunchToken) {
    return true;
  }

  return headerToken(request) === config.authToken;
}

/**
 * 校验 WebSocket 升级请求。
 * 除 Header 外，允许 query ?token= 以便浏览器/WebSocket 客户端传参。
 */
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
