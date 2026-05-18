# TypeScript Agent 网关

此目录用于本地 Node/TypeScript 网关进程。

## 职责

- 封装 Claude Agent SDK。
- 暴露本地 HTTP/WebSocket API。
- 管理应用级会话和 SDK session_id。
- 将 SDK 消息归一化为 Delphi 友好的事件。
- 桥接 `canUseTool`、工具审批和 `AskUserQuestion`。
- 记录审计日志和调试日志。

## 设计约束

- 默认只绑定 `127.0.0.1`。
- 所有请求必须携带 Delphi 启动时生成的 token。
- 不在仓库中保存 API key。
- 不直接向 Delphi 暴露 SDK 原始消息。
