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
import {
  SessionStore,
  toActiveGatewaySessionResponse,
  toSessionResponse,
  type GatewaySession
} from "../sessions/sessionStore.js";
import {
  createSdkSessionService,
  mapSdkSessionToResponse,
  mapSessionMessagesToHistory,
  type SdkSessionService
} from "../sessions/sdkSessionService.js";
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
  sessionStore?: SessionStore;
  sdkSessionService?: SdkSessionService;
};

export type GatewayServer = {
  start: () => Promise<void>;
  stop: () => Promise<void>;
  port: number;
};

type ActiveRun = {
  runId: string;
  abortController: AbortController;
};

export function createGatewayServer(options: GatewayServerOptions): GatewayServer {
  const { config, logger } = options;
  const agentRunner = options.agentRunner ?? createSdkAgentRunner();
  const sessionStore = options.sessionStore ?? new SessionStore();
  const sdkSessionService = options.sdkSessionService ?? createSdkSessionService();
  const subscribers = new Map<string, Set<WebSocket>>();
  const activeRuns = new Map<string, ActiveRun>();
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

      if (request.method === "GET" && url.pathname === "/api/sessions") {
        await handleListSessions(response, sessionStore, sdkSessionService, url);
        return;
      }

      const historyRoute = matchSessionHistoryRoute(url.pathname);
      if (request.method === "GET" && historyRoute) {
        await handleGetSessionHistory(
          response,
          sdkSessionService,
          historyRoute.sessionId,
          url
        );
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

      const stopRoute = matchSessionStopRoute(url.pathname);
      if (request.method === "POST" && stopRoute) {
        handleStopSession(response, sessionStore, subscribers, activeRuns, stopRoute.sessionId);
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
    start: async () => {
      await sessionStore.init();
      await new Promise<void>((resolve, reject) => {
        httpServer.once("error", reject);
        httpServer.listen(config.port, config.host, () => {
          httpServer.off("error", reject);
          resolve();
        });
      });
    },
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

  async function handleListSessions(
    response: http.ServerResponse,
    store: SessionStore,
    sdkSessions: SdkSessionService,
    url: URL
  ): Promise<void> {
    const workspacePath = readOptionalQueryString(url, "workspacePath");
    const limit = readOptionalQueryNumber(url, "limit");
    const offset = readOptionalQueryNumber(url, "offset");

    const sdkSessionList = await sdkSessions.listSessions({
      workspacePath,
      limit,
      offset
    });

    const sessions = mergeSessionList(
      sdkSessionList.map((info) => mapSdkSessionToResponse(info, workspacePath)),
      store
    );

    writeJson(response, 200, {
      protocolVersion: PROTOCOL_VERSION,
      sessions
    });
  }

  async function handleGetSessionHistory(
    response: http.ServerResponse,
    sdkSessions: SdkSessionService,
    sessionId: string,
    url: URL
  ): Promise<void> {
    const workspacePath = readOptionalQueryString(url, "workspacePath");
    const limit = readOptionalQueryNumber(url, "limit") ?? 200;
    const offset = readOptionalQueryNumber(url, "offset");

    const rawMessages = await sdkSessions.getSessionMessages(sessionId, {
      workspacePath,
      limit,
      offset
    });

    if (rawMessages.length === 0) {
      const info = await sdkSessions.getSessionInfo(sessionId, { workspacePath });
      if (!info) {
        writeError(response, 404, "session_not_found", "Session not found.");
        return;
      }
    }

    writeJson(response, 200, {
      protocolVersion: PROTOCOL_VERSION,
      sessionId,
      workspacePath,
      messages: mapSessionMessagesToHistory(rawMessages)
    });
  }

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
    await store.flush();
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

    const abortController = new AbortController();
    activeRuns.set(session.id, { runId, abortController });
    void runAgent(runner, store, runningSession, runId, body.prompt, abortController, activeRuns);
    writeJson(response, 202, {
      protocolVersion: PROTOCOL_VERSION,
      sessionId: session.id,
      runId,
      status: "running"
    });
  }

  function handleStopSession(
    response: http.ServerResponse,
    store: SessionStore,
    eventSubscribers: Map<string, Set<WebSocket>>,
    runs: Map<string, ActiveRun>,
    sessionId: string
  ): void {
    const session = store.get(sessionId);
    if (!session) {
      writeError(response, 404, "session_not_found", "Session not found.");
      return;
    }

    const activeRun = runs.get(sessionId);
    if (!activeRun) {
      writeError(response, 409, "session_not_running", "Session does not have a running task.");
      return;
    }

    activeRun.abortController.abort();
    runs.delete(sessionId);
    store.stopRun(sessionId);
    void store.flush();
    broadcast(eventSubscribers, createEvent(sessionId, activeRun.runId, "run_stopped", {
      reason: "user_cancelled",
      message: "Task stopped by user."
    }));
    logger.info("session_stopped", { sessionId, runId: activeRun.runId });
    writeJson(response, 200, {
      protocolVersion: PROTOCOL_VERSION,
      sessionId,
      runId: activeRun.runId,
      status: "stopped"
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
    prompt: string,
    abortController: AbortController,
    runs: Map<string, ActiveRun>
  ): Promise<void> {
    let terminalStatus: "idle" | "failed" | "stopped" = "idle";
    let sdkSessionId: string | undefined;
    let stoppedByUser = false;

    try {
      for await (const event of runner.run({
        session,
        sessionId: session.id,
        runId,
        prompt,
        abortController,
        approvals: approvalStore.createBridge(session.id, runId)
      })) {
        if (abortController.signal.aborted) {
          stoppedByUser = true;
          break;
        }

        broadcast(subscribers, event);
        if (event.type === "result") {
          sdkSessionId = typeof event.payload.sdkSessionId === "string"
            ? event.payload.sdkSessionId
            : undefined;
          terminalStatus = "idle";
        }
        if (event.type === "error") {
          sdkSessionId = typeof event.payload.sdkSessionId === "string"
            ? event.payload.sdkSessionId
            : sdkSessionId;
          terminalStatus = "failed";
        }
      }
    } catch (error: unknown) {
      if (abortController.signal.aborted) {
        stoppedByUser = true;
      } else {
        terminalStatus = "failed";
        broadcast(subscribers, createEvent(session.id, runId, "error", {
          code: "agent_error",
          message: error instanceof Error ? error.message : String(error),
          details: {}
        }));
      }
    } finally {
      runs.delete(session.id);
      if (stoppedByUser || abortController.signal.aborted) {
        store.stopRun(session.id);
      } else {
        store.finishRun(session.id, terminalStatus, sdkSessionId);
      }
      await store.flush();
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

function mergeSessionList(
  sdkSessions: ReturnType<typeof mapSdkSessionToResponse>[],
  store: SessionStore
): ReturnType<typeof mapSdkSessionToResponse>[] {
  const sdkIds = new Set(
    sdkSessions.flatMap((session) => [session.id, session.sdkSessionId].filter(Boolean) as string[])
  );
  const activeGatewaySessions = store.listActive()
    .filter((session) => !session.sdkSessionId || !sdkIds.has(session.sdkSessionId))
    .map(toActiveGatewaySessionResponse);

  return [...activeGatewaySessions, ...sdkSessions];
}

function readOptionalQueryString(url: URL, key: string): string | undefined {
  const value = url.searchParams.get(key);
  return value && value.trim() !== "" ? value : undefined;
}

function readOptionalQueryNumber(url: URL, key: string): number | undefined {
  const value = url.searchParams.get(key);
  if (!value) {
    return undefined;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function matchSessionHistoryRoute(pathname: string): { sessionId: string } | undefined {
  const match = /^\/api\/sessions\/([^/]+)\/history$/.exec(pathname);
  return match ? { sessionId: decodeURIComponent(match[1]) } : undefined;
}

function matchSessionMessageRoute(pathname: string): { sessionId: string } | undefined {
  const match = /^\/api\/sessions\/([^/]+)\/messages$/.exec(pathname);
  return match ? { sessionId: decodeURIComponent(match[1]) } : undefined;
}

function matchSessionStopRoute(pathname: string): { sessionId: string } | undefined {
  const match = /^\/api\/sessions\/([^/]+)\/stop$/.exec(pathname);
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
    case 409:
      return "Conflict";
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
