# VCL 桌面客户端

此目录用于 Delphi VCL Windows 桌面应用。

## 职责

- 提供原生 Windows 聊天界面。
- 启动和监控本地 TypeScript Agent 网关。
- 通过 HTTP 提交命令。
- 通过 WebSocket 接收会话事件。
- 展示工具审批和 `AskUserQuestion` 交互。

## 模块

- `src/App`：应用启动和依赖装配。
- `src/UI`：VCL 窗体和 Frame。
- `src/ViewModels`：UI 状态和命令状态。
- `src/Services`：网关进程、HTTP、WebSocket、设置持久化。
- `src/Protocol`：协议 DTO。
- `src/Utils`：通用工具。

## 阶段 2 运行方式

阶段 2 的开发期外壳连接已运行的本地网关，不直接启动 `node` 或 `npm` 子进程。后续发布期会把 `src/Services/GatewayProcessService.pas` 替换为真实子进程启动和 stdout readiness 解析。

1. 在 `apps/agent-gateway` 下构建并启动网关。
2. 记录网关 stdout 输出的 readiness JSON 中的 `port`。
3. 创建 `%APPDATA%\MzClaude\settings.json`：

```json
{
  "host": "127.0.0.1",
  "port": 39123,
  "authToken": "<gateway launch token>",
  "autoConnect": true
}
```

4. 使用 Delphi 12 打开 `MzClaude.dproj` 并启动 VCL 客户端。

客户端启动后会自动调用 `GET /api/health`，并在状态栏显示连接成功、未配置、鉴权失败、连接失败或响应解析失败。
