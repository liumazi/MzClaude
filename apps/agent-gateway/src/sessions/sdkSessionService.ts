import {
  getSessionInfo,
  getSessionMessages,
  listSessions,
  type SDKSessionInfo,
  type SessionMessage
} from "@anthropic-ai/claude-agent-sdk";

import { PROTOCOL_VERSION, type SessionHistoryMessage, type SessionResponse } from "../protocol/types.js";

export type ListSdkSessionsOptions = {
  workspacePath?: string;
  limit?: number;
  offset?: number;
};

export type GetSdkSessionHistoryOptions = {
  workspacePath?: string;
  limit?: number;
  offset?: number;
};

export type SdkSessionService = {
  listSessions: (options?: ListSdkSessionsOptions) => Promise<SDKSessionInfo[]>;
  getSessionMessages: (sessionId: string, options?: GetSdkSessionHistoryOptions) => Promise<SessionMessage[]>;
  getSessionInfo: (sessionId: string, options?: { workspacePath?: string }) => Promise<SDKSessionInfo | undefined>;
};

export function createSdkSessionService(): SdkSessionService {
  return {
    listSessions: (options) => listSdkSessions(options),
    getSessionMessages: (sessionId, options) => getSdkSessionHistory(sessionId, options),
    getSessionInfo: (sessionId, options) => getSdkSessionInfo(sessionId, options)
  };
}

export async function listSdkSessions(options: ListSdkSessionsOptions = {}): Promise<SDKSessionInfo[]> {
  const listOptions: Parameters<typeof listSessions>[0] = {
    limit: options.limit,
    offset: options.offset
  };

  if (options.workspacePath) {
    listOptions.dir = options.workspacePath;
  }

  return listSessions(listOptions);
}

export async function getSdkSessionHistory(
  sessionId: string,
  options: GetSdkSessionHistoryOptions = {}
): Promise<SessionMessage[]> {
  const messageOptions: Parameters<typeof getSessionMessages>[1] = {
    limit: options.limit,
    offset: options.offset
  };

  if (options.workspacePath) {
    messageOptions.dir = options.workspacePath;
  }

  return getSessionMessages(sessionId, messageOptions);
}

export async function getSdkSessionInfo(
  sessionId: string,
  options: { workspacePath?: string } = {}
): Promise<SDKSessionInfo | undefined> {
  const infoOptions: Parameters<typeof getSessionInfo>[1] = {};
  if (options.workspacePath) {
    infoOptions.dir = options.workspacePath;
  }

  return getSessionInfo(sessionId, infoOptions);
}

export function mapSdkSessionToResponse(
  info: SDKSessionInfo,
  fallbackWorkspace?: string
): SessionResponse {
  const workspacePath = info.cwd ?? fallbackWorkspace ?? "";
  const createdMs = info.createdAt ?? info.lastModified;
  const updatedMs = info.lastModified;

  return {
    protocolVersion: PROTOCOL_VERSION,
    id: info.sessionId,
    sdkSessionId: info.sessionId,
    workspacePath,
    title: info.customTitle ?? info.summary,
    status: "idle",
    createdAt: new Date(createdMs).toISOString(),
    updatedAt: new Date(updatedMs).toISOString()
  };
}

export function mapSessionMessagesToHistory(messages: SessionMessage[]): SessionHistoryMessage[] {
  const history: SessionHistoryMessage[] = [];

  for (const entry of messages) {
    const text = extractMessageText(entry.message);
    if (text.trim() === "" && entry.type !== "system") {
      continue;
    }

    history.push({
      role: entry.type,
      uuid: entry.uuid,
      sessionId: entry.session_id,
      text
    });
  }

  return history;
}

export function formatSessionHistoryTranscript(messages: SessionHistoryMessage[]): string {
  const lines: string[] = [];

  for (const message of messages) {
    if (message.text.trim() === "") {
      continue;
    }

    const label = message.role === "user"
      ? "User"
      : message.role === "assistant"
        ? "Assistant"
        : "System";
    lines.push(`[${label}]`, message.text, "");
  }

  return lines.join("\n").trimEnd();
}

export function extractMessageText(message: unknown): string {
  if (!isRecord(message)) {
    return "";
  }

  if (typeof message.content === "string") {
    return message.content;
  }

  if (!Array.isArray(message.content)) {
    return "";
  }

  const parts: string[] = [];
  for (const block of message.content) {
    if (!isRecord(block)) {
      continue;
    }

    if (block.type === "text" && typeof block.text === "string") {
      parts.push(block.text);
    }
  }

  return parts.join("\n");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
