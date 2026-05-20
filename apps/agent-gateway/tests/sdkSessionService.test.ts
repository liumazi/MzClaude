import test from "node:test";
import assert from "node:assert/strict";

import {
  extractMessageText,
  formatSessionHistoryTranscript,
  mapSdkSessionToResponse,
  mapSessionMessagesToHistory
} from "../src/sessions/sdkSessionService.js";
import type { SessionMessage } from "@anthropic-ai/claude-agent-sdk";

test("extractMessageText reads string and text block content", () => {
  assert.equal(extractMessageText({ content: "hello" }), "hello");
  assert.equal(
    extractMessageText({
      content: [
        { type: "text", text: "line one" },
        { type: "text", text: "line two" }
      ]
    }),
    "line one\nline two"
  );
});

test("mapSdkSessionToResponse maps SDK session metadata", () => {
  const response = mapSdkSessionToResponse({
    sessionId: "abc-123",
    summary: "Fix auth module",
    lastModified: 1_700_000_000_000,
    cwd: "D:\\Code\\proj",
    createdAt: 1_699_999_000_000
  });

  assert.equal(response.id, "abc-123");
  assert.equal(response.sdkSessionId, "abc-123");
  assert.equal(response.workspacePath, "D:\\Code\\proj");
  assert.equal(response.title, "Fix auth module");
  assert.equal(response.status, "idle");
});

test("mapSessionMessagesToHistory and formatSessionHistoryTranscript", () => {
  const messages: SessionMessage[] = [
    {
      type: "user",
      uuid: "u1",
      session_id: "abc",
      message: { content: [{ type: "text", text: "Hi" }] },
      parent_tool_use_id: null
    },
    {
      type: "assistant",
      uuid: "a1",
      session_id: "abc",
      message: { content: [{ type: "text", text: "Hello there" }] },
      parent_tool_use_id: null
    }
  ];

  const history = mapSessionMessagesToHistory(messages);
  assert.equal(history.length, 2);
  assert.equal(history[0].role, "user");
  assert.equal(history[0].text, "Hi");

  const transcript = formatSessionHistoryTranscript(history);
  assert.match(transcript, /\[User\]/);
  assert.match(transcript, /Hi/);
  assert.match(transcript, /\[Assistant\]/);
  assert.match(transcript, /Hello there/);
});
