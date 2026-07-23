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

在菜单栏点击「启用 Claude 集成」/「启用 Qoder 集成」即可把上报 hooks 合并写入对应客户端的 `settings.json`
（Claude Code → `~/.claude/settings.json`，Qoder → `~/.qoder/settings.json`；写前自动备份，可一键停用回滚）。
两者共用同一套 hook 机制，上报时按客户端区分计数。

> ⚠️ **启用集成后，需在对应客户端（Claude Code / Qoder）中新开一个会话**，hooks 才会加载生效——之后跑任务即可在菜单栏看到计数变化。

## 使用与交互

- **菜单栏**：猫图标 + `▶工作中 ⏸等待中 ✓已完成`；点开看「监控中 / 最近事件 / 集成状态 / 各客户端计数」。
- **桌面宠物**：小猫浮窗随状态变化；**右键小猫 →「隐藏宠物」**，之后从菜单栏「显示宠物」重新打开；可拖动。
- **能量/进化**：见下方「能量玩法」。

## 故障排查 / 诊断

看不到监控信息时，按顺序自查：

1. **命令行诊断**：`agentmon --doctor`（或菜单「运行诊断…」）打印一份报告——检查集成是否启用、上报器是否存在可执行、spool 是否可写、运行状态、最近日志、并给出建议。
2. **看日志**：菜单「打开日志文件」或 `~/Library/Application Support/agentmon/agentmon.log`（只记事件元数据，不含任务内容）。
3. **最常见原因**：启用集成后**没有新开 Claude Code 会话** → hooks 未加载 → 无事件。新开会话后再跑任务。

## 构建与运行

```bash
swift build                 # 编译 Core + App + agentmon-hook
swift test                  # 单元 + 集成测试（51 用例）
swift-format lint --recursive Sources tests   # 静态检查（经 xcrun）
swift scripts/make-icon.swift                 # 重新生成 App 图标

.build/debug/agentmon --selftest   # 无 GUI 自检：验证摄取→计数→能量链路
.build/debug/agentmon --doctor     # 无 GUI 打印诊断报告
.build/debug/agentmon              # 启动菜单栏 App + 桌面宠物（需图形会话）
```

## 项目结构

```
Sources/Core/    纯逻辑（可测，无 UI 依赖）：TaskStore / EnergyEngine / SpoolIngestor /
                 ClaudeHookInstaller / StateStore / MonitorCoordinator / Diagnostics / AgentmonLog
Sources/App/     菜单栏 App + 宠物浮窗（AppKit + SwiftUI）+ --selftest / --doctor
Sources/Hook/    agentmon-hook：Claude Code hook 上报器（读 stdin → 原子写 spool）
scripts/         package.sh（打 .app）· make-icon.swift（生成图标）
tests/unit/      单元测试     tests/integration/  集成测试     tests/e2e/  XCUITest 场景
```

## 能量玩法

| 事件 | 能量变化（默认，可配置） |
| --- | --- |
| 工作中任务 | `+2 / 分钟` |
| 等待中任务 | `−1 / 分钟` |
| 完成任务 | `+30`（一次性） |
| 无任务 | `−0.5 / 分钟` |

能量累计跨过门槛（默认 Lv2=300 / Lv3=900 / Lv4=2000）触发进化换肤；等级单调不回退。数值见 `config.json`（`~/Library/Application Support/agentmon/`）。
