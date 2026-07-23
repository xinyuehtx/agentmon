# tests/ —— TDD 测试用例（Step 5）

本目录按 AGENTS.md 工作流要求「单元测试与集成测试分目录组织」：

- `unit/` —— 纯逻辑单元测试（`EnergyEngineTests`、`TaskStoreTests`）
- `integration/` —— 跨文件/IO 集成测试（`SpoolIngestionTests`、`ClaudeHookInstallerTests`）
- `e2e/` —— 端到端（XCUITest）场景说明，见 [`e2e/README.md`](./e2e/README.md)（Step 9 落地）

> **当前状态：RED（预期）**。这些 XCTest 断言的是 `agentmonCore` 的接口契约（见
> [`specs/agent-task-monitor.md`](../specs/agent-task-monitor.md)），而 `agentmonCore` 与 Xcode 工程尚未创建。
> Step 7 实现时将创建工程、把本目录接入 `agentmonTests`/`agentmonUITests` target，使其转 GREEN。

测试仅依赖 `agentmonCore`（`@testable import agentmonCore`）与系统 `Foundation`/`XCTest`，无三方依赖。
