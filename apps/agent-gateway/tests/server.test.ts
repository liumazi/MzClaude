import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";

import WebSocket from "ws";

import { createLogger } from "../src/logging/logger.js";
import { createGatewayServer } from "../src/server/server.js";
import type { GatewayConfig } from "../src/config/config.js";
import type { AgentRunRequest } from "../src/agent/agentRunner.js";
import type { GatewayEvent } from "../src/protocol/types.js";
import { SessionStore } from "../src/sessions/sessionStore.js";

const baseConfig: GatewayConfig = {
  protocolVersion: 1,
  version: "0.1.0",
  host: "127.0.0.1",
  port: 0,
  authToken: "launch-token",
  dataDir: "C:\\Users\\test\\AppData\\Local\\MzClaude",
  security: {
    requireLaunchToken: true,
    allowRemoteHosts: false,
    redactSecretsInLogs: true
  }
};

function silentLogger() {
  return createLogger({
    redactSecrets: true,
    secrets: [baseConfig.authToken],
    write: () => undefined
  });
}

test("GET /api/health returns status, version, and config summary with a valid token", async () => {
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger()
  });
  await gateway.start();

  try {
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/health`, {
      headers: { Authorization: "Bearer launch-token" }
    });
    const body = await response.json() as {
      protocolVersion: number;
      status: string;
      version: string;
      config: {
        host: string;
        port: number;
        authRequired: boolean;
        dataDirConfigured: boolean;
      };
    };

    assert.equal(response.status, 200);
    assert.equal(body.protocolVersion, 1);
    assert.equal(body.status, "ok");
    assert.equal(body.version, "0.1.0");
    assert.equal(body.config.host, "127.0.0.1");
    assert.equal(body.config.port, gateway.port);
    assert.equal(body.config.authRequired, true);
    assert.equal(body.config.dataDirConfigured, true);
  } finally {
    await gateway.stop();
  }
});

test("GET /api/health rejects requests without a launch token", async () => {
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger()
  });
  await gateway.start();

  try {
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/health`);
    const body = await response.json() as {
      error: {
        code: string;
        message: string;
        details: Record<string, unknown>;
      };
    };

    assert.equal(response.status, 401);
    assert.equal(body.error.code, "unauthorized");
    assert.equal(body.error.message, "Missing or invalid launch token.");
    assert.deepEqual(body.error.details, {});
  } finally {
    await gateway.stop();
  }
});

test("WebSocket upgrades without a token are rejected before upgrade", async () => {
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger()
  });
  await gateway.start();

  try {
    const response = await sendRawUpgradeRequest(gateway.port);

    assert.match(response, /^HTTP\/1\.1 401 Unauthorized/);
    assert.match(response, /"code":"unauthorized"/);
  } finally {
    await gateway.stop();
  }
});

test("POST /api/sessions creates an idle session for a workspace", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger()
  });
  await gateway.start();

  try {
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ workspacePath, permissionPreset: "default" })
    });
    const body = await response.json() as {
      protocolVersion: number;
      id: string;
      workspacePath: string;
      status: string;
      createdAt: string;
      updatedAt: string;
    };

    assert.equal(response.status, 201);
    assert.equal(body.protocolVersion, 1);
    assert.match(body.id, /^sess_/);
    assert.equal(body.workspacePath, workspacePath);
    assert.equal(body.status, "idle");
    assert.ok(Date.parse(body.createdAt));
    assert.ok(Date.parse(body.updatedAt));
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/messages streams text_delta and result events", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* ({ sessionId, runId }): AsyncGenerator<GatewayEvent> {
        yield createTestEvent(sessionId, "text_delta", { text: "Hello " }, runId);
        yield createTestEvent(sessionId, "text_delta", { text: "from Claude" }, runId);
        yield createTestEvent(sessionId, "result", {
          status: "success",
          text: "Hello from Claude",
          sdkSessionId: "sdk-session-1"
        }, runId);
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const socket = new WebSocket(
      `ws://127.0.0.1:${gateway.port}/api/sessions/${session.id}/events?token=launch-token`
    );
    await waitForOpen(socket);

    const received = collectMessages(socket, 3);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Say hello" })
    });
    const accepted = await response.json() as { runId: string; status: string };
    const events = await received;

    assert.equal(response.status, 202);
    assert.match(accepted.runId, /^run_/);
    assert.equal(accepted.status, "running");
    assert.deepEqual(events.map((event) => event.type), ["text_delta", "text_delta", "result"]);
    assert.equal(events[0].payload.text, "Hello ");
    assert.equal(events[1].payload.text, "from Claude");
    assert.equal(events[2].payload.text, "Hello from Claude");
    assert.equal(events[2].payload.sdkSessionId, "sdk-session-1");

    socket.close();
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/messages rejects a second prompt while running", async () => {
  const workspacePath = await createTempWorkspace();
  let releaseRunner: (() => void) | undefined;
  const runnerCanFinish = new Promise<void>((resolve) => {
    releaseRunner = resolve;
  });
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* ({ sessionId, runId }): AsyncGenerator<GatewayEvent> {
        yield createTestEvent(sessionId, "text_delta", { text: "Working" }, runId);
        await runnerCanFinish;
        yield createTestEvent(sessionId, "result", { status: "success", text: "Done" }, runId);
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const first = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Start" })
    });
    const second = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Again" })
    });
    const body = await second.json() as {
      error: {
        code: string;
        message: string;
      };
    };

    assert.equal(first.status, 202);
    assert.equal(second.status, 409);
    assert.equal(body.error.code, "session_busy");
    assert.equal(body.error.message, "Session already has a running task.");
  } finally {
    releaseRunner?.();
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/messages emits an error event when the runner fails", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* (): AsyncGenerator<GatewayEvent> {
        throw new Error("synthetic runner failure");
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const socket = new WebSocket(
      `ws://127.0.0.1:${gateway.port}/api/sessions/${session.id}/events?token=launch-token`
    );
    await waitForOpen(socket);

    const received = collectMessages(socket, 1);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Fail" })
    });
    const events = await received;

    assert.equal(response.status, 202);
    assert.equal(events[0].type, "error");
    assert.equal(events[0].payload.code, "agent_error");
    assert.equal(events[0].payload.message, "synthetic runner failure");

    socket.close();
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/approvals/{requestId} allows a pending tool request to continue", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* (request): AsyncGenerator<GatewayEvent> {
        const approval = await request.approvals.requestPermission({
          toolName: "Bash",
          input: { command: "npm test" },
          title: "Claude wants to run npm test"
        });

        if (approval.behavior === "deny") {
          yield createTestEvent(request.sessionId, "error", {
            code: "permission_denied",
            message: approval.message
          }, request.runId);
          return;
        }

        yield createTestEvent(request.sessionId, "result", {
          status: "success",
          text: "Tool approved"
        }, request.runId);
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const socket = new WebSocket(
      `ws://127.0.0.1:${gateway.port}/api/sessions/${session.id}/events?token=launch-token`
    );
    await waitForOpen(socket);

    const firstEvent = receiveNextEvent(socket);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Run tests" })
    });
    const permissionEvent = await firstEvent;

    assert.equal(response.status, 202);
    assert.equal(permissionEvent.type, "permission_request");
    assert.equal(permissionEvent.payload.toolName, "Bash");
    assert.equal(permissionEvent.payload.title, "Claude wants to run npm test");
    assert.equal(typeof permissionEvent.payload.requestId, "string");

    const resultEvent = receiveNextEvent(socket);
    const approvalResponse = await postApproval(
      gateway.port,
      session.id,
      String(permissionEvent.payload.requestId),
      { action: "allow" }
    );
    const result = await resultEvent;

    assert.equal(approvalResponse.status, 200);
    assert.equal(result.type, "result");
    assert.equal(result.payload.text, "Tool approved");

    socket.close();
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/approvals/{requestId} returns a denial reason to the runner", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* (request): AsyncGenerator<GatewayEvent> {
        const approval = await request.approvals.requestPermission({
          toolName: "Write",
          input: { file_path: "danger.txt" }
        });

        if (approval.behavior === "deny") {
          yield createTestEvent(request.sessionId, "error", {
            code: "permission_denied",
            message: approval.message
          }, request.runId);
        }
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const socket = new WebSocket(
      `ws://127.0.0.1:${gateway.port}/api/sessions/${session.id}/events?token=launch-token`
    );
    await waitForOpen(socket);

    const permissionEventPromise = receiveNextEvent(socket);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Write a file" })
    });
    const permissionEvent = await permissionEventPromise;

    assert.equal(response.status, 202);
    assert.equal(permissionEvent.type, "permission_request");

    const errorEventPromise = receiveNextEvent(socket);
    const approvalResponse = await postApproval(
      gateway.port,
      session.id,
      String(permissionEvent.payload.requestId),
      { action: "deny", reason: "Do not change files." }
    );
    const errorEvent = await errorEventPromise;

    assert.equal(approvalResponse.status, 200);
    assert.equal(errorEvent.type, "error");
    assert.equal(errorEvent.payload.code, "permission_denied");
    assert.equal(errorEvent.payload.message, "Do not change files.");

    socket.close();
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("GET /api/sessions returns recent sessions ordered by updatedAt", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: { ...baseConfig, dataDir: undefined },
    logger: silentLogger(),
    sessionStore: new SessionStore()
  });
  await gateway.start();

  try {
    const first = await createSession(gateway.port, workspacePath);
    const second = await createSession(gateway.port, workspacePath);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions`, {
      headers: jsonHeaders()
    });
    const body = await response.json() as {
      protocolVersion: number;
      sessions: { id: string; workspacePath: string }[];
    };

    assert.equal(response.status, 200);
    assert.equal(body.protocolVersion, 1);
    assert.equal(body.sessions.length, 2);
    assert.equal(body.sessions[0].id, second.id);
    assert.equal(body.sessions[1].id, first.id);
    assert.equal(body.sessions[0].workspacePath, workspacePath);
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("GET /api/sessions survives gateway restart when dataDir is configured", async () => {
  const workspacePath = await createTempWorkspace();
  const dataDir = await fs.mkdtemp(path.join(os.tmpdir(), "mzclaude-gateway-data-"));
  const config: GatewayConfig = {
    ...baseConfig,
    dataDir
  };

  const firstGateway = createGatewayServer({
    config,
    logger: silentLogger(),
    sessionStore: new SessionStore(dataDir)
  });
  await firstGateway.start();

  let sessionId = "";
  try {
    const session = await createSession(firstGateway.port, workspacePath);
    sessionId = session.id;
    await new Promise((resolve) => setTimeout(resolve, 50));
  } finally {
    await firstGateway.stop();
  }

  const secondGateway = createGatewayServer({
    config,
    logger: silentLogger(),
    sessionStore: new SessionStore(dataDir)
  });
  await secondGateway.start();

  try {
    const response = await fetch(`http://127.0.0.1:${secondGateway.port}/api/sessions`, {
      headers: jsonHeaders()
    });
    const body = await response.json() as {
      sessions: { id: string; status: string }[];
    };

    assert.equal(response.status, 200);
    assert.equal(body.sessions.length, 1);
    assert.equal(body.sessions[0].id, sessionId);
    assert.equal(body.sessions[0].status, "idle");
  } finally {
    await secondGateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
    await fs.rm(dataDir, { recursive: true, force: true });
  }
});

test("POST /api/sessions persists sdkSessionId after a successful run", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* ({ sessionId, runId }): AsyncGenerator<GatewayEvent> {
        yield createTestEvent(sessionId, "result", {
          status: "success",
          text: "Done",
          sdkSessionId: "sdk-session-42"
        }, runId);
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Hello" })
    });

    await waitFor(async () => {
      const listResponse = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions`, {
        headers: jsonHeaders()
      });
      const listBody = await listResponse.json() as {
        sessions: { id: string; sdkSessionId?: string; status: string }[];
      };
      return listBody.sessions[0]?.sdkSessionId === "sdk-session-42"
        && listBody.sessions[0]?.status === "idle";
    });
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions accepts resumeSessionId for SDK resume", async () => {
  const workspacePath = await createTempWorkspace();
  let capturedResume: string | undefined;
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* (request: AgentRunRequest): AsyncGenerator<GatewayEvent> {
        capturedResume = request.session.resumeSessionId ?? request.session.sdkSessionId;
        yield createTestEvent(request.sessionId, "result", { status: "success", text: "ok" }, request.runId);
      }
    }
  });
  await gateway.start();

  try {
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ workspacePath, resumeSessionId: "sdk-resume-1" })
    });
    const session = await response.json() as { id: string };

    assert.equal(response.status, 201);
    await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Continue" })
    });

    await waitFor(async () => capturedResume === "sdk-resume-1");
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/stop emits run_stopped and cancels the runner", async () => {
  const workspacePath = await createTempWorkspace();
  let releaseRunner: (() => void) | undefined;
  const runnerCanFinish = new Promise<void>((resolve) => {
    releaseRunner = resolve;
  });
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* (request: AgentRunRequest): AsyncGenerator<GatewayEvent> {
        yield createTestEvent(request.sessionId, "text_delta", { text: "Working" }, request.runId);
        await Promise.race([
          runnerCanFinish,
          new Promise<void>((resolve) => {
            request.abortController?.signal.addEventListener("abort", () => resolve(), { once: true });
          })
        ]);

        if (request.abortController?.signal.aborted) {
          return;
        }

        yield createTestEvent(request.sessionId, "result", { status: "success", text: "Done" }, request.runId);
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const socket = new WebSocket(
      `ws://127.0.0.1:${gateway.port}/api/sessions/${session.id}/events?token=launch-token`
    );
    await waitForOpen(socket);

    const eventsPromise = collectMessages(socket, 2);
    await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Start" })
    });

    const stopResponse = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/stop`, {
      method: "POST",
      headers: jsonHeaders()
    });
    const events = await eventsPromise;
    const stopEvent = events.find((event) => event.type === "run_stopped");
    const stopBody = await stopResponse.json() as {
      sessionId: string;
      status: string;
      runId: string;
    };

    assert.equal(stopResponse.status, 200);
    assert.equal(stopBody.status, "stopped");
    assert.ok(stopEvent);
    assert.equal(stopEvent?.type, "run_stopped");
    assert.equal(stopEvent?.payload.reason, "user_cancelled");

    const listResponse = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions`, {
      headers: jsonHeaders()
    });
    const listBody = await listResponse.json() as {
      sessions: { id: string; status: string }[];
    };
    assert.equal(listBody.sessions[0].status, "stopped");

    socket.close();
  } finally {
    releaseRunner?.();
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/stop rejects when session is not running", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger()
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/stop`, {
      method: "POST",
      headers: jsonHeaders()
    });
    const body = await response.json() as {
      error: { code: string; message: string };
    };

    assert.equal(response.status, 409);
    assert.equal(body.error.code, "session_not_running");
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

test("POST /api/sessions/{id}/approvals/{requestId} answers a pending question request", async () => {
  const workspacePath = await createTempWorkspace();
  const gateway = createGatewayServer({
    config: baseConfig,
    logger: silentLogger(),
    agentRunner: {
      run: async function* (request): AsyncGenerator<GatewayEvent> {
        const answer = await request.approvals.requestQuestion({
          questions: [
            {
              question: "Which test target should run?",
              header: "Target",
              multiSelect: false,
              options: [
                { label: "Unit", description: "Run unit tests" },
                { label: "All", description: "Run every test" }
              ]
            }
          ]
        });

        yield createTestEvent(request.sessionId, "result", {
          status: "success",
          text: answer.answers["Which test target should run?"]
        }, request.runId);
      }
    }
  });
  await gateway.start();

  try {
    const session = await createSession(gateway.port, workspacePath);
    const socket = new WebSocket(
      `ws://127.0.0.1:${gateway.port}/api/sessions/${session.id}/events?token=launch-token`
    );
    await waitForOpen(socket);

    const questionEventPromise = receiveNextEvent(socket);
    const response = await fetch(`http://127.0.0.1:${gateway.port}/api/sessions/${session.id}/messages`, {
      method: "POST",
      headers: jsonHeaders(),
      body: JSON.stringify({ prompt: "Ask me" })
    });
    const questionEvent = await questionEventPromise;

    assert.equal(response.status, 202);
    const questions = questionEvent.payload.questions as { question: string }[];
    assert.equal(questionEvent.type, "question_request");
    assert.equal(questions[0].question, "Which test target should run?");

    const resultEventPromise = receiveNextEvent(socket);
    const approvalResponse = await postApproval(
      gateway.port,
      session.id,
      String(questionEvent.payload.requestId),
      {
        action: "answer_question",
        answers: {
          "Which test target should run?": "All"
        }
      }
    );
    const resultEvent = await resultEventPromise;

    assert.equal(approvalResponse.status, 200);
    assert.equal(resultEvent.type, "result");
    assert.equal(resultEvent.payload.text, "All");

    socket.close();
  } finally {
    await gateway.stop();
    await fs.rm(workspacePath, { recursive: true, force: true });
  }
});

function sendRawUpgradeRequest(port: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: "127.0.0.1", port }, () => {
      socket.write([
        "GET /api/sessions/sess_01/events HTTP/1.1",
        "Host: 127.0.0.1",
        "Connection: Upgrade",
        "Upgrade: websocket",
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
        "Sec-WebSocket-Version: 13",
        "",
        ""
      ].join("\r\n"));
    });

    let data = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => {
      data += chunk;
    });
    socket.on("error", reject);
    socket.on("end", () => resolve(data));
    socket.setTimeout(2000, () => {
      socket.destroy(new Error("Timed out waiting for upgrade response"));
    });
  });
}

function jsonHeaders(): Record<string, string> {
  return {
    Authorization: "Bearer launch-token",
    "Content-Type": "application/json",
    Accept: "application/json"
  };
}

async function createTempWorkspace(): Promise<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), "mzclaude-workspace-"));
}

async function createSession(port: number, workspacePath: string): Promise<{ id: string }> {
  const response = await fetch(`http://127.0.0.1:${port}/api/sessions`, {
    method: "POST",
    headers: jsonHeaders(),
    body: JSON.stringify({ workspacePath })
  });

  assert.equal(response.status, 201);
  return response.json() as Promise<{ id: string }>;
}

function createTestEvent(
  sessionId: string,
  type: GatewayEvent["type"],
  payload: Record<string, unknown>,
  runId: string
): GatewayEvent {
  return {
    protocolVersion: 1,
    sessionId,
    runId,
    type,
    timestamp: new Date().toISOString(),
    payload
  };
}

function waitForOpen(socket: WebSocket): Promise<void> {
  return new Promise((resolve, reject) => {
    socket.once("open", () => resolve());
    socket.once("error", reject);
  });
}

function collectMessages(socket: WebSocket, count: number): Promise<GatewayEvent[]> {
  return new Promise((resolve, reject) => {
    const events: GatewayEvent[] = [];
    socket.on("message", (data) => {
      events.push(JSON.parse(data.toString()) as GatewayEvent);
      if (events.length === count) {
        resolve(events);
      }
    });
    socket.once("error", reject);
  });
}

function receiveNextEvent(socket: WebSocket): Promise<GatewayEvent> {
  return new Promise((resolve, reject) => {
    socket.once("message", (data) => {
      resolve(JSON.parse(data.toString()) as GatewayEvent);
    });
    socket.once("error", reject);
  });
}

function postApproval(
  port: number,
  sessionId: string,
  requestId: string,
  body: Record<string, unknown>
): Promise<Response> {
  return fetch(`http://127.0.0.1:${port}/api/sessions/${sessionId}/approvals/${requestId}`, {
    method: "POST",
    headers: jsonHeaders(),
    body: JSON.stringify(body)
  });
}

async function waitFor(predicate: () => boolean | Promise<boolean>, timeoutMs = 3000): Promise<void> {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    if (await predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }

  throw new Error("Timed out waiting for condition.");
}
