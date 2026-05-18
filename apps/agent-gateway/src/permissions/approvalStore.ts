import crypto from "node:crypto";

import type { ElicitationResult, PermissionResult } from "@anthropic-ai/claude-agent-sdk";

import {
  PROTOCOL_VERSION,
  type GatewayEvent,
  type PermissionRequestPayload,
  type QuestionRequestItem,
  type QuestionRequestPayload,
  type SubmitApprovalRequest
} from "../protocol/types.js";

export type PermissionApprovalRequest = Omit<PermissionRequestPayload, "requestId">;

export type QuestionApprovalRequest = {
  questions: QuestionRequestItem[];
};

export type ApprovalBridge = {
  requestPermission(request: PermissionApprovalRequest): Promise<PermissionResult>;
  requestQuestion(request: QuestionApprovalRequest): Promise<QuestionAnswerResult>;
  requestElicitation(request: ElicitationApprovalRequest): Promise<ElicitationResult>;
};

export type QuestionAnswerResult = {
  questions: QuestionRequestItem[];
  answers: Record<string, string>;
  annotations?: Record<string, { preview?: string; notes?: string }>;
};

export type ElicitationApprovalRequest = {
  serverName: string;
  message: string;
  mode?: "form" | "url";
  url?: string;
  requestedSchema?: Record<string, unknown>;
  title?: string;
  displayName?: string;
  description?: string;
};

export type ApprovalResolution =
  | {
      ok: true;
    }
  | {
      ok: false;
      statusCode: number;
      code: string;
      message: string;
    };

type PendingApproval =
  | {
      kind: "permission";
      sessionId: string;
      resolve: (result: PermissionResult) => void;
    }
  | {
      kind: "question";
      sessionId: string;
      questions: QuestionRequestItem[];
      resolve: (result: QuestionAnswerResult) => void;
    }
  | {
      kind: "elicitation";
      sessionId: string;
      resolve: (result: ElicitationResult) => void;
    };

export class ApprovalStore {
  private readonly pending = new Map<string, PendingApproval>();

  constructor(private readonly emit: (event: GatewayEvent) => void) {
  }

  createBridge(sessionId: string, runId: string): ApprovalBridge {
    return {
      requestPermission: (request) => this.requestPermission(sessionId, runId, request),
      requestQuestion: (request) => this.requestQuestion(sessionId, runId, request),
      requestElicitation: (request) => this.requestElicitation(sessionId, runId, request)
    };
  }

  resolve(sessionId: string, requestId: string, request: SubmitApprovalRequest): ApprovalResolution {
    const pending = this.pending.get(requestId);
    if (!pending) {
      return {
        ok: false,
        statusCode: 404,
        code: "approval_not_found",
        message: "Approval request not found."
      };
    }

    if (pending.sessionId !== sessionId) {
      return {
        ok: false,
        statusCode: 404,
        code: "approval_not_found",
        message: "Approval request not found."
      };
    }

    if (pending.kind === "permission") {
      return this.resolvePermission(requestId, pending, request);
    }

    if (pending.kind === "question") {
      return this.resolveQuestion(requestId, pending, request);
    }

    return this.resolveElicitation(requestId, pending, request);
  }

  private requestPermission(
    sessionId: string,
    runId: string,
    request: PermissionApprovalRequest
  ): Promise<PermissionResult> {
    const requestId = createRequestId("perm");
    const payload: PermissionRequestPayload = {
      requestId,
      ...request
    };

    const promise = new Promise<PermissionResult>((resolve) => {
      this.pending.set(requestId, { kind: "permission", sessionId, resolve });
    });

    this.emit(createEvent(sessionId, runId, "permission_request", payload));
    return promise;
  }

  private requestQuestion(
    sessionId: string,
    runId: string,
    request: QuestionApprovalRequest
  ): Promise<QuestionAnswerResult> {
    const requestId = createRequestId("ques");
    const payload: QuestionRequestPayload = {
      requestId,
      questions: request.questions
    };

    const promise = new Promise<QuestionAnswerResult>((resolve) => {
      this.pending.set(requestId, {
        kind: "question",
        sessionId,
        questions: request.questions,
        resolve
      });
    });

    this.emit(createEvent(sessionId, runId, "question_request", payload));
    return promise;
  }

  private requestElicitation(
    sessionId: string,
    runId: string,
    request: ElicitationApprovalRequest
  ): Promise<ElicitationResult> {
    const requestId = createRequestId("elic");
    const questions = [
      {
        question: request.message,
        header: request.displayName ?? request.serverName,
        multiSelect: false,
        options: [
          { label: "Accept", description: request.title ?? "Accept the request" },
          { label: "Decline", description: request.description ?? "Decline the request" }
        ]
      }
    ];

    const promise = new Promise<ElicitationResult>((resolve) => {
      this.pending.set(requestId, { kind: "elicitation", sessionId, resolve });
    });

    this.emit(createEvent(sessionId, runId, "question_request", {
      requestId,
      questions,
      elicitation: {
        serverName: request.serverName,
        mode: request.mode,
        url: request.url,
        requestedSchema: request.requestedSchema
      }
    }));
    return promise;
  }

  private resolvePermission(
    requestId: string,
    pending: Extract<PendingApproval, { kind: "permission" }>,
    request: SubmitApprovalRequest
  ): ApprovalResolution {
    if (request.action === "allow") {
      this.pending.delete(requestId);
      pending.resolve({ behavior: "allow" });
      return { ok: true };
    }

    if (request.action === "allow_with_changes") {
      this.pending.delete(requestId);
      pending.resolve({ behavior: "allow", updatedInput: request.updatedInput });
      return { ok: true };
    }

    if (request.action === "deny") {
      this.pending.delete(requestId);
      pending.resolve({ behavior: "deny", message: request.reason });
      return { ok: true };
    }

    return {
      ok: false,
      statusCode: 400,
      code: "invalid_approval_action",
      message: "Permission requests require allow, allow_with_changes, or deny."
    };
  }

  private resolveQuestion(
    requestId: string,
    pending: Extract<PendingApproval, { kind: "question" }>,
    request: SubmitApprovalRequest
  ): ApprovalResolution {
    if (request.action === "deny") {
      this.pending.delete(requestId);
      pending.resolve({
        questions: pending.questions,
        answers: {}
      });
      return { ok: true };
    }

    if (request.action !== "answer_question") {
      return {
        ok: false,
        statusCode: 400,
        code: "invalid_approval_action",
        message: "Question requests require answer_question or deny."
      };
    }

    this.pending.delete(requestId);
    pending.resolve({
      questions: pending.questions,
      answers: request.answers,
      annotations: request.annotations
    });
    return { ok: true };
  }

  private resolveElicitation(
    requestId: string,
    pending: Extract<PendingApproval, { kind: "elicitation" }>,
    request: SubmitApprovalRequest
  ): ApprovalResolution {
    if (request.action === "deny") {
      this.pending.delete(requestId);
      pending.resolve({ action: "decline" });
      return { ok: true };
    }

    if (request.action === "answer_question") {
      this.pending.delete(requestId);
      pending.resolve({ action: "accept", content: request.answers });
      return { ok: true };
    }

    return {
      ok: false,
      statusCode: 400,
      code: "invalid_approval_action",
      message: "Elicitation requests require answer_question or deny."
    };
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

function createRequestId(prefix: string): string {
  return `${prefix}_${crypto.randomUUID().replace(/-/g, "")}`;
}
