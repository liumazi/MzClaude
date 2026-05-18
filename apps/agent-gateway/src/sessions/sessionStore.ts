import crypto from "node:crypto";

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

export class SessionStore {
  private readonly sessions = new Map<string, GatewaySession>();

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

  finishRun(id: string, status: Extract<SessionStatus, "idle" | "failed">, sdkSessionId?: string): void {
    const session = this.sessions.get(id);
    if (!session) {
      return;
    }

    session.status = status;
    session.currentRunId = undefined;
    session.sdkSessionId = sdkSessionId ?? session.sdkSessionId;
    session.updatedAt = new Date().toISOString();
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
