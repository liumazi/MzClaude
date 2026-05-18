export const PROTOCOL_VERSION = 1 as const;

export type ErrorResponse = {
  error: {
    code: string;
    message: string;
    details: Record<string, unknown>;
  };
};

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

export type SessionStatus = "idle" | "running" | "waiting_for_approval" | "stopped" | "failed";

export type PermissionPreset = "plan" | "default" | "readOnly";

export type CreateSessionRequest = {
  workspacePath: string;
  permissionPreset?: PermissionPreset;
  model?: string;
  resumeSessionId?: string;
};

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

export type SendMessageRequest = {
  prompt: string;
};

export type SendMessageResponse = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  runId: string;
  status: "running";
};

export type ApprovalAction = "allow" | "allow_with_changes" | "deny" | "answer_question";

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

export type QuestionRequestPayload = {
  requestId: string;
  questions: QuestionRequestItem[];
};

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

export type GatewayEvent = {
  protocolVersion: typeof PROTOCOL_VERSION;
  sessionId: string;
  runId?: string;
  type: GatewayEventType;
  timestamp: string;
  payload: Record<string, unknown>;
};
