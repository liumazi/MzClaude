/**
 * 网关侧内存会话表：跟踪当前进程内创建的会话及运行状态。
 * 历史会话列表与持久化由 Claude Agent SDK 负责，本存储不写入磁盘。
 */
import crypto from "node:crypto";

import {
  PROTOCOL_VERSION,
  type CreateSessionRequest,
  type SessionResponse,
  type SessionStatus
} from "../protocol/types.js";

/** 网关内部会话实体（比 API SessionResponse 字段更多） */
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

/** 一次 run 结束后的终态（不含 running / waiting_for_approval） */
type TerminalRunStatus = Extract<SessionStatus, "idle" | "failed" | "stopped">;

const ACTIVE_STATUSES: SessionStatus[] = ["running", "waiting_for_approval"];

export class SessionStore {
  private readonly sessions = new Map<string, GatewaySession>();
  private initialized = false;

  async init(): Promise<void> {
    this.initialized = true;
  }

  /** 创建新会话，默认 permissionPreset 为 default，状态 idle */
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

  /** 按 updatedAt 降序返回全部内存会话 */
  list(): GatewaySession[] {
    return [...this.sessions.values()].sort(
      (left, right) => Date.parse(right.updatedAt) - Date.parse(left.updatedAt)
    );
  }

  /** 仅返回正在执行或等待审批的会话，用于与 SDK 列表合并 */
  listActive(): GatewaySession[] {
    return this.list().filter((session) => ACTIVE_STATUSES.includes(session.status));
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

  /** Agent 正常结束：写入 SDK sessionId 并恢复 idle/failed/stopped */
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

  /** 用户主动停止或 abort 后的状态 */
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
    // 仅占位：持久化由 SDK 完成，此处无 I/O
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

/**
 * 列表合并用：进行中会话若尚未有 sdkSessionId，用 resumeSessionId 作为对外 id 便于续聊。
 */
export function toActiveGatewaySessionResponse(session: GatewaySession): SessionResponse {
  return {
    ...toSessionResponse(session),
    id: session.id,
    sdkSessionId: session.sdkSessionId ?? session.resumeSessionId
  };
}
