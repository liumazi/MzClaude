# 共享协议

此目录存放 Delphi VCL 客户端和 TypeScript Agent 网关之间共享的协议定义。

## 目录

- `schemas`：JSON Schema 草案，用于描述命令、事件和错误结构。
- `examples`：示例 payload，便于 Delphi 和 TypeScript 两端对齐实现。

## 约定

- 所有消息都包含 `protocolVersion`。
- HTTP 错误和 WebSocket 错误使用相同的错误对象结构。
- WebSocket 事件使用 `type` 字段区分事件种类。
- SDK 原始消息不直接暴露给 Delphi，必须先在网关归一化。
