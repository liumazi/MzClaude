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

function normalizePermissionMode(permissionPreset: string) {
  if (permissionPreset === "readOnly") {
    return "plan";
  }

  if (permissionPreset === "plan") {
    return "plan";
  }

  return "default";
}

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
