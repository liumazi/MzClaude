# MVP 实施拆分

## 阶段 1：协议和网关骨架

目标：让 TypeScript 网关可以启动、暴露健康检查、校验 token，并定义稳定的协议模型。

交付：

- HTTP server 和 WebSocket server 骨架。
- `GET /api/health`。
- 协议 schema 和示例 payload。
- 错误响应模型。
- 基础日志结构。

验证：

- 健康检查返回版本和状态。
- 无 token 请求被拒绝。
- schema 示例可以被校验。

## 阶段 2：Delphi 客户端外壳

目标：VCL 应用可以启动网关、连接健康检查，并展示基础 shell。

交付：

- 主窗体。
- 网关进程启动服务。
- HTTP client 服务。
- 基础设置加载。
- 状态栏展示网关连接状态。

验证：

- 启动客户端后自动启动网关。
- 网关异常退出时 UI 能显示错误状态。

## 阶段 3：流式聊天闭环

目标：用户可以选择工作区、创建会话、发送 prompt，并看到流式文本。

交付：

- `POST /api/sessions`。
- `POST /api/sessions/{id}/messages`。
- `GET /api/sessions/{id}/events` WebSocket。
- Agent SDK `query()` 封装。
- `text_delta`、`result`、`error` 事件。

验证：

- 可以完成一次真实或 mock SDK 的流式聊天。
- 任务完成后 UI 状态回到可输入。

## 阶段 4：权限审批和问题交互

目标：SDK 请求工具权限或澄清问题时，Delphi UI 可以暂停、展示并返回决策。

交付：

- `canUseTool` 桥接。
- `permission_request` 和 `question_request` 事件。
- `POST /api/sessions/{id}/approvals/{requestId}`。
- VCL 审批对话框和多选问题对话框。

验证：

- 用户允许工具后任务继续。
- 用户拒绝工具后 SDK 收到拒绝原因。
- `AskUserQuestion` 能返回选项结果。

## 阶段 5：会话恢复与取消

目标：支持最近会话列表、恢复 SDK session_id，并能停止运行中的任务。

交付：

- `GET /api/sessions`。
- session 元数据存储。
- SDK session_id 捕获和恢复。
- `POST /api/sessions/{id}/stop`。
- `run_stopped` 事件。

验证：

- 重启应用后能看到最近会话。
- 可以按 session_id 恢复上下文。
- 用户停止任务后 SDK 查询被取消。

## 阶段 6：发布准备

目标：形成可分发的 Windows 桌面包。

交付：

- 网关子进程打包方案。
- Delphi 启动参数和 readiness 解析。
- 本地数据目录策略。
- 最小端到端冒烟测试清单。

验证：

- 清洁机器上可以启动桌面应用和网关。
- 可以完成创建会话、发送 prompt、审批工具、停止任务的冒烟流程。
