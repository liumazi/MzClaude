import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import type { AddressInfo } from "node:net";

import WebSocket, { WebSocketServer } from "ws";

import { createSdkAgentRunner, type AgentRunner } from "../agent/agentRunner.js";
import type { GatewayConfig } from "../config/config.js";
import type { Logger } from "../logging/logger.js";
import type {
  CreateSessionRequest,
  GatewayEvent,
  HealthResponse,
  SendMessageRequest,
  SubmitApprovalRequest
} from "../protocol/types.js";
import { PROTOCOL_VERSION } from "../protocol/types.js";
import { ApprovalStore } from "../permissions/approvalStore.js";
import { SessionStore, toSessionResponse, type GatewaySession } from "../sessions/sessionStore.js";
import {
  isHttpRequestAuthorized,
  isWebSocketRequestAuthorized,
  UNAUTHORIZED_MESSAGE
} from "./auth.js";
import { BodyReadError, readJsonBody } from "./body.js";
import { createErrorResponse, writeError, writeJson } from "./errors.js";

export type GatewayServerOptions = {
  config: GatewayConfig;
  logger: Logger;
  agentRunner?: AgentRunner;
};

export type GatewayServer = {
  start: () => Promise<void>;
  stop: () => Promise<void>;
  port: number;
};

export function createGatewayServer(options: GatewayServerOptions): GatewayServer {
  const { config, logger } = options;
  const agentRunner = options.agentRunner ?? createSdkAgentRunner();
  const sessionStore = new SessionStore();
  const subscribers = new Map<string, Set<WebSocket>>();
  const approvalStore = new ApprovalStore((event) => broadcast(subscribers, event));
  const webSocketServer = new WebSocketServer({ noServer: true });

  const httpServer = http.createServer(async (request, response) => {
    const url = new URL(request.url ?? "/", `http://${config.host}`);

    if (!isHttpRequestAuthorized(request, config)) {
      logger.warn("http_unauthorized", { method: request.method, path: url.pathname });
      writeError(response, 401, "unauthorized", UNAUTHORIZED_MESSAGE);
      return;
    }

    try {
      if (request.method === "GET" && url.pathname === "/api/health") {
        logger.info("health_checked", { path: url.pathname });
        writeJson(response, 200, createHealthResponse(config, gateway.port));
        return;
      }

      if (request.method === "POST" && url.pathname === "/api/sessions") {
        await handleCreateSession(request, response, sessionStore);
        return;
      }

      const messageRoute = matchSessionMessageRoute(url.pathname);
      if (request.method === "POST" && messageRoute) {
        await handleSendMessage(request, response, sessionStore, agentRunner, messageRoute.sessionId);
        return;
      }

      const approvalRoute = matchSessionApprovalRoute(url.pathname);
      if (request.method === "POST" && approvalRoute) {
        await handleSubmitApproval(request, response, sessionStore, approvalRoute.sessionId, approvalRoute.requestId);
        return;
      }

      writeError(response, 404, "not_found", "Route not found.", { path: url.pathname });
    } catch (error: unknown) {
      if (error instanceof BodyReadError) {
        writeError(response, 400, error.code, error.message);
        return;
      }

      logger.error("http_request_failed", {
        method: request.method,
        path: url.pathname,
        error: error instanceof Error ? error.message : String(error)
      });
      writeError(response, 500, "internal_error", "Gateway request failed.");
    }
  });

  httpServer.on("upgrade", (request, socket, head) => {
    const url = new URL(request.url ?? "/", `http://${config.host}`);

    if (!isWebSocketRequestAuthorized(request, url, config)) {
      logger.warn("websocket_unauthorized", { path: url.pathname, url: request.url });
      const body = JSON.stringify(createErrorResponse("unauthorized", UNAUTHORIZED_MESSAGE));
      socket.write([
        "HTTP/1.1 401 Unauthorized",
        "Content-Type: application/json; charset=utf-8",
        `Content-Length: ${Buffer.byteLength(body)}`,
        "Connection: close",
        "",
        body
      ].join("\r\n"));
      socket.end();
      return;
    }

    const eventsRoute = matchSessionEventsRoute(url.pathname);
    if (!eventsRoute) {
      writeUpgradeError(socket, 404, "not_found", "WebSocket route not found.");
      return;
    }

    const session = sessionStore.get(eventsRoute.sessionId);
    if (!session) {
      writeUpgradeError(socket, 404, "session_not_found", "Session not found.");
      return;
    }

    webSocketServer.handleUpgrade(request, socket, head, (webSocket) => {
      logger.info("websocket_connected", { path: url.pathname, sessionId: session.id });
      subscribe(subscribers, session.id, webSocket);
    });
  });

  const gateway: GatewayServer = {
    start: () => new Promise((resolve, reject) => {
      httpServer.once("error", reject);
      httpServer.listen(config.port, config.host, () => {
        httpServer.off("error", reject);
        resolve();
      });
    }),
    stop: () => new Promise((resolve, reject) => {
      webSocketServer.clients.forEach((client) => client.close());
      webSocketServer.close((webSocketError) => {
        if (webSocketError) {
          reject(webSocketError);
          return;
        }

        httpServer.close((httpError) => {
          if (httpError) {
            reject(httpError);
            return;
          }

          resolve();
        });
      });
    }),
    get port() {
      const address = httpServer.address() as AddressInfo | null;
      return address?.port ?? config.port;
    }
  };

  return gateway;

  async function handleCreateSession(
    request: http.IncomingMessage,
    response: http.ServerResponse,
    store: SessionStore
  ): Promise<void> {
    const body = await readJsonBody(request);
    if (!isCreateSessionRequest(body)) {
      writeError(response, 400, "invalid_request", "workspacePath is required.");
      return;
    }

    if (!await isDirectory(body.workspacePath)) {
      writeError(response, 400, "invalid_workspace", "workspacePath must be an existing directory.");
      return;
    }

    const session = store.create(body);
    logger.info("session_created", { sessionId: session.id, workspacePath: session.workspacePath });
    writeJson(response, 201, toSessionResponse(session));
  }

  async function handleSendMessage(
    request: http.IncomingMessage,
    response: http.ServerResponse,
    store: SessionStore,
    runner: AgentRunner,
    sessionId: string
  ): Promise<void> {
    const session = store.get(sessionId);
    if (!session) {
      writeError(response, 404, "session_not_found", "Session not found.");
      return;
    }

    if (session.status === "running") {
      writeError(response, 409, "session_busy", "Session already has a running task.");
      return;
    }

    const body = await readJsonBody(request);
    if (!isSendMessageRequest(body)) {
      writeError(response, 400, "invalid_request", "prompt is required.");
      return;
    }

    const runId = `run_${crypto.randomUUID().replace(/-/g, "")}`;
    const runningSession = store.startRun(session.id, runId);
    if (!runningSession) {
      writeError(response, 404, "session_not_found", "Session not found.");
      return;
    }

    void runAgent(runner, store, runningSession, runId, body.prompt);
    writeJson(response, 202, {
      protocolVersion: PROTOCOL_VERSION,
      sessionId: session.id,
      runId,
      status: "running"
    });
  }

  async function handleSubmitApproval(
    request: http.IncomingMessage,
    response: http.ServerResponse,
    store: SessionStore,
    sessionId: string,
    requestId: string
  ): Promise<void> {
    const session = store.get(sessionId);
    if (!session) {
      writeError(response, 404, "session_not_found", "Session not found.");
      return;
    }

    const body = await readJsonBody(request);
    if (!isSubmitApprovalRequest(body)) {
      writeError(response, 400, "invalid_request", "Approval action is invalid.");
      return;
    }

    const result = approvalStore.resolve(session.id, requestId, body);
    if (!result.ok) {
      writeError(response, result.statusCode, result.code, result.message);
      return;
    }

    logger.info("approval_submitted", { sessionId: session.id, requestId, action: body.action });
    writeJson(response, 200, {
      protocolVersion: PROTOCOL_VERSION,
      sessionId: session.id,
      requestId,
      status: "accepted"
    });
  }

  async function runAgent(
    runner: AgentRunner,
    store: SessionStore,
    session: GatewaySession,
    runId: string,
    prompt: string
  ): Promise<void> {
    let terminalStatus: "idle" | "failed" = "idle";
    let sdkSessionId: string | undefined;

    try {
      for await (const event of runner.run({
        session,
        sessionId: session.id,
        runId,
        prompt,
        approvals: approvalStore.createBridge(session.id, runId)
      })) {
        broadcast(subscribers, event);
        if (event.type === "result") {
          sdkSessionId = typeof event.payload.sdkSessionId === "string"
            ? event.payload.sdkSessionId
            : undefined;
          terminalStatus = "idle";
        }
        if (event.type === "error") {
          terminalStatus = "failed";
        }
      }
    } catch (error: unknown) {
      terminalStatus = "failed";
      broadcast(subscribers, createEvent(session.id, runId, "error", {
        code: "agent_error",
        message: error instanceof Error ? error.message : String(error),
        details: {}
      }));
    } finally {
      store.finishRun(session.id, terminalStatus, sdkSessionId);
    }
  }
}

function createHealthResponse(config: GatewayConfig, port: number): HealthResponse {
  return {
    protocolVersion: PROTOCOL_VERSION,
    status: "ok",
    version: config.version,
    config: {
      host: config.host,
      port,
      authRequired: config.security.requireLaunchToken,
      dataDirConfigured: Boolean(config.dataDir)
    }
  };
}

function isCreateSessionRequest(value: unknown): value is CreateSessionRequest {
  if (!isRecord(value) || typeof value.workspacePath !== "string" || value.workspacePath.trim() === "") {
    return false;
  }

  if (value.permissionPreset !== undefined
    && value.permissionPreset !== "default"
    && value.permissionPreset !== "plan"
    && value.permissionPreset !== "readOnly") {
    return false;
  }

  return (value.model === undefined || typeof value.model === "string")
    && (value.resumeSessionId === undefined || typeof value.resumeSessionId === "string");
}

function isSendMessageRequest(value: unknown): value is SendMessageRequest {
  return isRecord(value) && typeof value.prompt === "string" && value.prompt.trim() !== "";
}

function isSubmitApprovalRequest(value: unknown): value is SubmitApprovalRequest {
  if (!isRecord(value) || typeof value.action !== "string") {
    return false;
  }

  if (value.action === "allow") {
    return true;
  }

  if (value.action === "allow_with_changes") {
    return isRecord(value.updatedInput);
  }

  if (value.action === "deny") {
    return typeof value.reason === "string";
  }

  if (value.action === "answer_question") {
    return isStringRecord(value.answers)
      && (value.annotations === undefined || isRecord(value.annotations));
  }

  return false;
}

async function isDirectory(path: string): Promise<boolean> {
  try {
    const stat = await fs.stat(path);
    return stat.isDirectory();
  } catch {
    return false;
  }
}

function matchSessionMessageRoute(pathname: string): { sessionId: string } | undefined {
  const match = /^\/api\/sessions\/([^/]+)\/messages$/.exec(pathname);
  return match ? { sessionId: decodeURIComponent(match[1]) } : undefined;
}

function matchSessionEventsRoute(pathname: string): { sessionId: string } | undefined {
  const match = /^\/api\/sessions\/([^/]+)\/events$/.exec(pathname);
  return match ? { sessionId: decodeURIComponent(match[1]) } : undefined;
}

function matchSessionApprovalRoute(pathname: string): { sessionId: string; requestId: string } | undefined {
  const match = /^\/api\/sessions\/([^/]+)\/approvals\/([^/]+)$/.exec(pathname);
  return match
    ? { sessionId: decodeURIComponent(match[1]), requestId: decodeURIComponent(match[2]) }
    : undefined;
}

function subscribe(subscribers: Map<string, Set<WebSocket>>, sessionId: string, socket: WebSocket): void {
  const sessionSubscribers = subscribers.get(sessionId) ?? new Set<WebSocket>();
  sessionSubscribers.add(socket);
  subscribers.set(sessionId, sessionSubscribers);

  socket.once("close", () => {
    sessionSubscribers.delete(socket);
    if (sessionSubscribers.size === 0) {
      subscribers.delete(sessionId);
    }
  });
}

function broadcast(subscribers: Map<string, Set<WebSocket>>, event: GatewayEvent): void {
  const sessionSubscribers = subscribers.get(event.sessionId);
  if (!sessionSubscribers) {
    return;
  }

  const text = JSON.stringify(event);
  for (const socket of sessionSubscribers) {
    if (socket.readyState === WebSocket.OPEN) {
      socket.send(text);
    }
  }
}

function createEvent(
  sessionId: string,
  runId: string,
  type: GatewayEvent["type"],
  payload: Record<string, unknown>
): GatewayEvent {
  return {
    protocolVersion: PROTOCOL_VERSION,
    sessionId,
    runId,
    type,
    timestamp: new Date().toISOString(),
    payload
  };
}

function writeUpgradeError(
  socket: NodeJS.WritableStream,
  statusCode: number,
  code: string,
  message: string
): void {
  const body = JSON.stringify(createErrorResponse(code, message));
  socket.write([
    `HTTP/1.1 ${statusCode} ${statusText(statusCode)}`,
    "Content-Type: application/json; charset=utf-8",
    `Content-Length: ${Buffer.byteLength(body)}`,
    "Connection: close",
    "",
    body
  ].join("\r\n"));
  socket.end();
}

function statusText(statusCode: number): string {
  switch (statusCode) {
    case 400:
      return "Bad Request";
    case 401:
      return "Unauthorized";
    case 404:
      return "Not Found";
    default:
      return "Error";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isStringRecord(value: unknown): value is Record<string, string> {
  if (!isRecord(value)) {
    return false;
  }

  return Object.values(value).every((item) => typeof item === "string");
}
