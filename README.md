# agentmon 🐱

> Agent 小精灵 —— 一个 macOS 上的 Agent 长任务监控工具，用一只 AI 原创小猫陪你一起「养成」。

agentmon 监控本地已安装的 Agent 客户端（Claude Code、Qoder、QoderWorker、Codex 等）长任务的**启动 / 暂停 / 结束**状态，并以两种形态呈现：

- **菜单栏（menubar）**：实时展示每个客户端「工作中 / 等待中 / 已完成」的任务数量。
- **桌面小工具（宠物）**：一只小猫随你的工作状态积累或消耗能量，能量达到门槛即可**进化（换肤）**。

## 开发工作流

本仓库遵循 [`AGENTS.md`](./AGENTS.md) 定义的 10 步协作工作流（方案 → RFC → SPEC/Story/测试 → 审查 → 实现 → 验证 → 沉淀）。

- 技术栈：原生 Swift（SwiftPM 包；macOS 13+ 菜单栏 App + 桌面宠物浮窗）
- 需求文档：[`rfcs/`](./rfcs) · [`specs/`](./specs) · [`stories/`](./stories) · [`blog/`](./blog)

## 构建与运行

```bash
swift build                 # 编译 Core + App + agentmon-hook
swift test                  # 单元 + 集成测试（45 用例）
swift-format lint --recursive Sources tests   # 静态检查（经 xcrun）

.build/debug/agentmon --selftest   # 无 GUI 自检：验证摄取→计数→能量链路
.build/debug/agentmon              # 启动菜单栏 App + 桌面宠物（需图形会话）
```

在菜单栏点击「启用 Claude 集成」即可把上报 hooks 合并写入 `~/.claude/settings.json`（写前自动备份，可一键停用回滚）。

## 项目结构

```
Sources/Core/    纯逻辑（可测，无 UI 依赖）：TaskStore / EnergyEngine / SpoolIngestor /
                 ClaudeHookInstaller / StateStore / MonitorCoordinator
Sources/App/     菜单栏 App + 宠物浮窗（AppKit + SwiftUI）+ --selftest
Sources/Hook/    agentmon-hook：Claude Code hook 上报器（读 stdin → 原子写 spool）
tests/unit/      单元测试     tests/integration/  集成测试     tests/e2e/  XCUITest 场景（待落地）
```

## 能量玩法

| 事件 | 能量变化（默认，可配置） |
| --- | --- |
| 工作中任务 | `+2 / 分钟` |
| 等待中任务 | `−1 / 分钟` |
| 完成任务 | `+30`（一次性） |
| 无任务 | `−0.5 / 分钟` |

能量累计跨过门槛（默认 Lv2=300 / Lv3=900 / Lv4=2000）触发进化换肤；等级单调不回退。数值见 `config.json`（`~/Library/Application Support/agentmon/`）。
