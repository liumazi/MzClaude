# MzClaude

MzClaude 是一个规划中的 Windows 桌面 Agent 客户端：Delphi VCL 负责原生界面，本地 TypeScript 网关负责调用 Claude Agent SDK。

## 当前结构

- `apps/desktop-vcl`：Delphi VCL 桌面客户端。
- `apps/agent-gateway`：TypeScript Agent SDK 本地网关。
- `packages/protocol`：Delphi 与 TypeScript 共享的协议 schema 和示例。
- `docs`：架构、API、打包和 MVP 拆分文档。
- `config`：可提交的默认 Agent 配置。

## 设计文档

- `docs/architecture.md`
- `docs/api.md`
- `docs/packaging.md`
- `docs/mvp.md`