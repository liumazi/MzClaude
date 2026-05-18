# 打包与运行策略

## 开发模式

开发阶段分开运行 Delphi VCL 客户端和 TypeScript 网关。

推荐流程：

1. 在 `apps/agent-gateway` 下启动网关。
2. 网关绑定 `127.0.0.1` 和一个开发端口。
3. VCL 客户端从开发配置读取端口和 token。
4. 使用网关日志和浏览器/HTTP 工具调试协议。

这种方式便于独立测试 TypeScript 网关，也避免 Delphi 调试时反复重启 Node 进程。

## 发布模式

发布时，TypeScript 网关应打包为可执行子进程，由 Delphi 客户端启动和监控。

启动参数建议：

```text
agent-gateway --host 127.0.0.1 --port 0 --auth-token <token> --data-dir <path>
```

约定：

- `--port 0` 表示由系统分配可用端口。
- `--auth-token` 由 Delphi 每次启动随机生成。
- `--data-dir` 指向用户本地应用数据目录。
- 网关启动后向 stdout 输出一次 JSON readiness 信息，包含实际端口和版本。

## 进程生命周期

Delphi 客户端负责：

- 启动网关子进程。
- 读取 readiness 信息。
- 定期调用 `GET /api/health`。
- 应用退出时关闭网关。
- 网关异常退出时提示用户，并标记当前运行任务失败。

网关负责：

- 只监听本机地址。
- 校验 token。
- 收到终止信号时取消所有运行中的任务。
- 刷新必要的会话元数据和审计日志。

## 本地数据目录

具体目录后续确定，候选：

- `%LOCALAPPDATA%\\MzClaude`
- `%APPDATA%\\MzClaude`

建议将缓存、日志和临时运行数据放在 `%LOCALAPPDATA%`，将用户可迁移的配置放在 `%APPDATA%`。

## 凭据处理

API key 不应写入仓库或默认配置文件。首版优先读取环境变量：

- `ANTHROPIC_API_KEY`
- 第三方提供商相关环境变量，例如 Bedrock、Vertex AI 或 Azure Foundry 配置。

后续如需要 GUI 配置，可接入 Windows Credential Manager 或其他 OS 凭据存储。

## 后续待选打包工具

TypeScript 网关可执行文件的打包工具暂不在首版文档中锁定。后续需要评估：

- Node 运行时体积。
- 原生依赖支持。
- Claude Agent SDK 可选依赖的打包行为。
- Windows 签名和杀毒误报风险。
