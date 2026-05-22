/**
 * 网关与桌面客户端之间的 HTTP/WebSocket 协议类型定义。
 * 所有响应均携带 protocolVersion 以便版本协商。
 */
export const PROTOCOL_VERSION = 1 as const;

/** 统一错误响应体 */
export type ErrorResponse = {
  error: {
    code: string;
    message: string;
    details: Record<string, unknown>;
  };
};

/** GET /api/health */
export type HealthResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  status: "ok";
  version: string;
  config: {
    host: string;
    port: number;
    authRequired: boolean;
    dataDirConfigured: boolean;
  };
};

/** 会话生命周期状态 */
export type SessionStatus = "idle" | "running" | "waiting_for_approval" | "stopped" | "failed";

/** 创建会话时的权限预设（映射到 SDK permissionMode） */
export type PermissionPreset = "plan" | "default" | "readOnly";

/** POST /api/sessions 请求体 */
export type CreateSessionRequest = {
  workspacePath: string;
  permissionPreset?: PermissionPreset;
  model?: string;
  resumeSessionId?: string;
};

/** 单条会话摘要 */
export type SessionResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  id: string;
  sdkSessionId?: string;
  workspacePath: string;
  title?: string;
  status: SessionStatus;
  createdAt: string;
  updatedAt: string;
};

/** GET /api/sessions */
export type SessionListResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessions: SessionResponse[];
};

/** 历史消息条目（由 SDK 消息映射而来） */
export type SessionHistoryMessage = {
  role: "user" | "assistant" | "system";
  uuid: string;
  sessionId: string;
  text: string;
};

/** GET /api/sessions/:id/history */
export type SessionHistoryResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  workspacePath?: string;
  messages: SessionHistoryMessage[];
};

/** POST /api/sessions/:id/stop */
export type StopSessionResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  runId?: string;
  status: "stopped";
};

/** POST /api/sessions/:id/messages */
export type SendMessageRequest = {
  prompt: string;
};

export type SendMessageResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  runId: string;
  status: "running";
};

/** 用户对待审批项的操作类型 */
export type ApprovalAction = "allow" | "allow_with_changes" | "deny" | "answer_question";

/** POST /api/sessions/:id/approvals/:requestId */
export type SubmitApprovalRequest =
  | {
      action: "allow";
    }
  | {
      action: "allow_with_changes";
      updatedInput: Record<string, unknown>;
    }
  | {
      action: "deny";
      reason: string;
    }
  | {
      action: "answer_question";
      answers: Record<string, string>;
      annotations?: Record<string, { preview?: string; notes?: string }>;
    };

export type SubmitApprovalResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  requestId: string;
  status: "accepted";
};

export type QuestionOption = {
  label: string;
  description: string;
  preview?: string;
};

export type QuestionRequestItem = {
  question: string;
  header: string;
  options: QuestionOption[];
  multiSelect: boolean;
};

/** WebSocket permission_request 事件载荷 */
export type PermissionRequestPayload = {
  requestId: string;
  toolName: string;
  input: Record<string, unknown>;
  suggestions?: unknown[];
  title?: string;
  displayName?: string;
  description?: string;
  blockedPath?: string;
  decisionReason?: string;
  toolUseId?: string;
  agentId?: string;
};

/** WebSocket question_request 事件载荷 */
export type QuestionRequestPayload = {
  requestId: string;
  questions: QuestionRequestItem[];
};

/** WebSocket 推送的事件类型 */
export type GatewayEventType =
  | "session_started"
  | "text_delta"
  | "tool_started"
  | "tool_delta"
  | "tool_finished"
  | "permission_request"
  | "question_request"
  | "permission_denied"
  | "result"
  | "error"
  | "run_stopped";

/** WebSocket /api/sessions/:id/events 下行消息 */
export type GatewayEvent = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  runId?: string;
  type: GatewayEventType;
  timestamp: string;
  payload: Record<string, unknown>;
};
