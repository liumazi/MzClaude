/**
 * Agent 执行器：通过 Claude Agent SDK query 驱动单次 run，
 * 将 SDK 流式消息映射为网关 GatewayEvent，并经 ApprovalBridge 处理工具权限与用户问答。
 */
import { query, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";

import { PROTOCOL_VERSION, type GatewayEvent } from "../protocol/types.js";
import type { ApprovalBridge } from "../permissions/approvalStore.js";
import type { GatewaySession } from "../sessions/sessionStore.js";

export type AgentRunRequest = {
  session: GatewaySession;
  sessionId: string;
  runId: string;
  prompt: string;
  approvals: ApprovalBridge;
  abortController?: AbortController;
};

export type AgentRunner = {
  run(request: AgentRunRequest): AsyncIterable<GatewayEvent>;
};

export function createSdkAgentRunner(): AgentRunner {
  return {
    async *run(request: AgentRunRequest): AsyncGenerator<GatewayEvent> {
      const sdkQuery = query({
        prompt: request.prompt,
        options: {
          cwd: request.session.workspacePath,
          includePartialMessages: true,
          permissionMode: normalizePermissionMode(request.session.permissionPreset),
          model: request.session.model,
          resume: request.session.resumeSessionId ?? request.session.sdkSessionId,
          abortController: request.abortController,
          // 工具调用前挂起，等待桌面端审批后 resolve
          canUseTool: (toolName, input, options) => request.approvals.requestPermission({
            toolName,
            input,
            suggestions: options.suggestions,
            blockedPath: options.blockedPath,
            decisionReason: options.decisionReason,
            title: options.title,
            displayName: options.displayName,
            description: options.description,
            toolUseId: options.toolUseID,
            agentId: options.agentID
          }),
          onElicitation: (elicitation) => request.approvals.requestElicitation({
            serverName: elicitation.serverName,
            message: elicitation.message,
            mode: elicitation.mode,
            url: elicitation.url,
            requestedSchema: elicitation.requestedSchema,
            title: elicitation.title,
            displayName: elicitation.displayName,
            description: elicitation.description
          })
        }
      });

      for await (const message of sdkQuery) {
        yield* mapSdkMessage(request.sessionId, request.runId, message);
      }
    }
  };
}

/** 网关 permissionPreset 与 SDK permissionMode 的对应关系 */
function normalizePermissionMode(permissionPreset: string) {
  if (permissionPreset === "readOnly") {
    return "plan";
  }

  if (permissionPreset === "plan") {
    return "plan";
  }

  return "default";
}

/** 将 SDKMessage 转为零个或多个 GatewayEvent（流式仅产出 text_delta） */
function* mapSdkMessage(sessionId: string, runId: string, message: SDKMessage): Generator<GatewayEvent> {
  if (message.type === "stream_event") {
    const text = extractTextDelta(message.event);
    if (text) {
      yield createEvent(sessionId, runId, "text_delta", { text });
    }
    return;
  }

  if (message.type === "result") {
    if (message.is_error) {
      yield createEvent(sessionId, runId, "error", {
        code: message.subtype,
        message: "Claude query failed.",
        details: {
          errors: "errors" in message ? message.errors : [],
          sdkSessionId: message.session_id
        }
      });
      return;
    }

    yield createEvent(sessionId, runId, "result", {
      status: "success",
      text: "result" in message ? message.result : "",
      sdkSessionId: message.session_id,
      durationMs: message.duration_ms,
      costUsd: message.total_cost_usd
    });
  }
}

function extractTextDelta(event: unknown): string {
  if (!isRecord(event)) {
    return "";
  }

  if (event.type === "content_block_delta" && isRecord(event.delta)) {
    return typeof event.delta.text === "string" ? event.delta.text : "";
  }

  if (event.type === "text_delta") {
    return typeof event.text === "string" ? event.text : "";
  }

  return "";
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
