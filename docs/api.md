# 本地 Agent 网关 API

## 协议原则

网关使用 HTTP 处理一次性命令，使用 WebSocket 推送实时事件。

HTTP 适合表达“做一件事”：创建会话、发送 prompt、停止任务、提交审批。这些操作需要清晰的请求体、响应码、错误语义和审计日志。

WebSocket 适合表达“订阅状态变化”：流式文本、工具调用状态、权限请求、澄清问题、最终结果和错误。

## 连接约定

网关监听本机地址：

```text
http://127.0.0.1:<port>
ws://127.0.0.1:<port>
```

`GET /api/sessions/{id}/events` 不是返回单独的 WebSocket 端口，而是同一网关端口上的 WebSocket 升级端点。`{id}` 用来标识订阅哪个会话的事件流。

示例：

```text
ws://127.0.0.1:39123/api/sessions/sess_123/events?token=<launch-token>
```

## HTTP 端点

### `GET /api/health`

返回网关就绪状态、版本和运行配置摘要。

### `POST /api/sessions`

创建应用级会话。

请求字段：

- `workspacePath`：目标工作区路径。
- `permissionPreset`：权限预设，例如 `plan`、`default`、`readOnly`。
- `model`：可选模型配置。
- `resumeSessionId`：可选 SDK session_id，用于恢复历史上下文。

### `GET /api/sessions`

列出网关已知会话。数据来源可以包括网关元数据和 Agent SDK 的会话发现能力。

### `POST /api/sessions/{id}/messages`

向空闲会话提交一个 prompt。若会话已有任务运行，应返回冲突错误，避免同一会话并发写入。

### `POST /api/sessions/{id}/stop`

取消当前运行。TypeScript 网关应通过 `AbortController` 中止正在执行的 SDK 查询。

### `POST /api/sessions/{id}/approvals/{requestId}`

响应工具审批或 `AskUserQuestion`。

审批行为包括：

- `allow`：允许原始工具调用。
- `allow_with_changes`：允许但替换工具输入。
- `deny`：拒绝并附带原因。
- `answer_question`：返回 `AskUserQuestion` 的选项结果。

## WebSocket 事件

WebSocket 传递网关归一化后的事件，不直接暴露 SDK 原始消息结构。`includePartialMessages` 只是事件来源之一。

首版事件类型：

- `session_started`：会话初始化，包含应用会话 ID、SDK session_id 和工作区。
- `text_delta`：助手文本增量。
- `tool_started`：工具调用开始。
- `tool_delta`：工具参数或执行进度增量。
- `tool_finished`：工具调用结束。
- `permission_request`：`canUseTool` 触发的审批请求。
- `question_request`：`AskUserQuestion` 触发的澄清问题。
- `permission_denied`：权限系统自动拒绝的工具请求。
- `result`：最终结果、状态、耗时、费用和 SDK session_id。
- `error`：协议错误、网关错误或 SDK 错误。
- `run_stopped`：用户取消或任务停止。

## 错误模型

HTTP 错误响应使用统一结构：

```json
{
  "error": {
    "code": "session_busy",
    "message": "Session already has a running task.",
    "details": {}
  }
}
```

WebSocket 错误使用 `error` 事件，并携带同样的 `code`、`message` 和 `details` 字段。

## 协议版本

所有请求和事件都应携带协议版本，首版使用：

```text
protocolVersion: 1
```

后续如需破坏性变更，应新增版本或在网关启动时声明兼容范围。
