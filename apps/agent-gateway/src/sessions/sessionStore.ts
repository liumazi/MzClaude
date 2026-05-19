import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import {
  PROTOCOL_VERSION,
  type CreateSessionRequest,
  type SessionResponse,
  type SessionStatus
} from "../protocol/types.js";

export type GatewaySession = {
  id: string;
  sdkSessionId?: string;
  workspacePath: string;
  permissionPreset: string;
  model?: string;
  resumeSessionId?: string;
  status: SessionStatus;
  createdAt: string;
  updatedAt: string;
  currentRunId?: string;
};

type TerminalRunStatus = Extract<SessionStatus, "idle" | "failed" | "stopped">;

export class SessionStore {
  private readonly sessions = new Map<string, GatewaySession>();
  private readonly dataDir?: string;
  private initialized = false;

  constructor(dataDir?: string) {
    this.dataDir = dataDir;
  }

  async init(): Promise<void> {
    if (this.initialized) {
      return;
    }

    this.initialized = true;
    await this.loadFromDisk();
  }

  create(request: CreateSessionRequest): GatewaySession {
    const now = new Date().toISOString();
    const session: GatewaySession = {
      id: `sess_${crypto.randomUUID().replace(/-/g, "")}`,
      workspacePath: request.workspacePath,
      permissionPreset: request.permissionPreset ?? "default",
      model: request.model,
      resumeSessionId: request.resumeSessionId,
      status: "idle",
      createdAt: now,
      updatedAt: now
    };

    this.sessions.set(session.id, session);
    return session;
  }

  get(id: string): GatewaySession | undefined {
    return this.sessions.get(id);
  }

  list(): GatewaySession[] {
    return [...this.sessions.values()].sort(
      (left, right) => Date.parse(right.updatedAt) - Date.parse(left.updatedAt)
    );
  }

  startRun(id: string, runId: string): GatewaySession | undefined {
    const session = this.sessions.get(id);
    if (!session) {
      return undefined;
    }

    session.status = "running";
    session.currentRunId = runId;
    session.updatedAt = new Date().toISOString();
    return session;
  }

  finishRun(
    id: string,
    status: TerminalRunStatus,
    sdkSessionId?: string
  ): void {
    const session = this.sessions.get(id);
    if (!session) {
      return;
    }

    session.status = status;
    session.currentRunId = undefined;
    session.sdkSessionId = sdkSessionId ?? session.sdkSessionId;
    session.updatedAt = new Date().toISOString();
  }

  stopRun(id: string): GatewaySession | undefined {
    const session = this.sessions.get(id);
    if (!session) {
      return undefined;
    }

    session.status = "stopped";
    session.currentRunId = undefined;
    session.updatedAt = new Date().toISOString();
    return session;
  }

  async flush(): Promise<void> {
    if (!this.dataDir) {
      return;
    }

    await Promise.all([...this.sessions.values()].map((session) => this.persist(session)));
  }

  private async loadFromDisk(): Promise<void> {
    if (!this.dataDir) {
      return;
    }

    const sessionsDir = path.join(this.dataDir, "sessions");
    let entries: string[];
    try {
      entries = await fs.readdir(sessionsDir);
    } catch {
      return;
    }

    for (const entry of entries) {
      if (!entry.endsWith(".json")) {
        continue;
      }

      try {
        const raw = await fs.readFile(path.join(sessionsDir, entry), "utf8");
        const session = JSON.parse(raw) as GatewaySession;
        if (session.status === "running") {
          session.status = "stopped";
          session.currentRunId = undefined;
        }
        this.sessions.set(session.id, session);
        await this.persist(session);
      } catch {
        // Skip corrupt session files.
      }
    }
  }

  private async persist(session: GatewaySession): Promise<void> {
    if (!this.dataDir) {
      return;
    }

    const sessionsDir = path.join(this.dataDir, "sessions");
    await fs.mkdir(sessionsDir, { recursive: true });
    const filePath = path.join(sessionsDir, `${session.id}.json`);
    const payload: GatewaySession = {
      ...session,
      currentRunId: undefined
    };
    await fs.writeFile(filePath, JSON.stringify(payload, null, 2), "utf8");
  }
}

export function toSessionResponse(session: GatewaySession): SessionResponse {
  return {
    protocolVersion: PROTOCOL_VERSION,
    id: session.id,
    sdkSessionId: session.sdkSessionId,
    workspacePath: session.workspacePath,
    status: session.status,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt
  };
}
