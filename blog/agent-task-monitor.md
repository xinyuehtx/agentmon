# 从 0 到 1：给 Agent 长任务做一只会进化的监控小猫

> 需求 slug：`agent-task-monitor` ｜ 关联：[RFC](../rfcs/agent-task-monitor.md) · [SPEC](../specs/agent-task-monitor.md) · [Story](../stories/agent-task-monitor.md)

这是 agentmon 的第一个需求落地记录，按 [`AGENTS.md`](../AGENTS.md) 的 10 步工作流走完了「方案 → RFC → SPEC/Story/测试 → 审查 → 实现 → 回归 → 沉淀」。本文沉淀关键决策与踩坑，方便后续 Agent / 同学快速接手。

## 1. 需求背景

开发者常同时开着多个 Agent 客户端（Claude Code、Qoder、QoderWorker、Codex…）跑长任务，缺乏统一的「谁在跑 / 谁卡住 / 谁跑完」的感知。agentmon 用一只 AI 原创小猫做养成式监控：把散落的任务态汇成菜单栏计数 + 桌面宠物，用能量/进化把「健康的工作节奏」变成正反馈。

首版范围（MVP）：只监控**启动 / 暂停 / 结束**三态；**Claude Code 做完整**，其余客户端留适配器骨架。

## 2. 技术方案要点

分层：**采集 Adapters → 状态引擎 Core → 展示 UI**，Core 与 UI/IO 解耦。

- **采集**：Claude Code hooks（`UserPromptSubmit`=启动 / `Notification`=暂停 / `Stop`=结束）→ 一个随包分发的 `agentmon-hook` 把事件**原子写**进 spool 目录（temp+rename）→ App 端 `SpoolIngestor` 读入即删。无端口、无网络、可断点续传。
- **状态**：`TaskStore` 维护每会话三态 + 每客户端计数；`EnergyEngine` 按速率结算能量与进化。
- **能量模型**：工作 `+2/min`、等待 `−1/min`、完成 `+30`、空闲 `−0.5/min`，能量下限 0；`level` **单调不回退**；门槛 `[300,900,2000]`，超出按 ×2 递推。
- **集成安全**：写用户 `~/.claude/settings.json` 前**备份**、按 `agentmon-hook` 标记**幂等**注入 / 精确回滚、JSON 损坏时**中止不写**。
- **展示**：`MenuBarExtra` 风格的 `NSStatusItem` 计数 + `NSPanel` 透明置顶宠物浮窗（SwiftUI 程序化画的小猫，Lv1 灰猫 / Lv2 金猫换肤）。

工程用 **SwiftPM**（`agentmonCore` 库 + `agentmon` App + `agentmon-hook`），核心逻辑全部落在可测的 Core 里。

## 3. 关键设计决策

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| 技术栈 | 原生 Swift | 用户指定；最原生的菜单栏 + 浮窗 + 低占用 |
| 宠物形态 | NSPanel 浮窗，非 WidgetKit | WidgetKit 撑不起连续动画与实时互动 |
| 事件传输 | drop-file spool，非 HTTP/socket | 免端口冲突、进程隔离、天然持久化、最易测试 |
| 进化 | `level` 单调不回退 | 养成不惩罚——坏日子只停滞进度，不掉级劝退 |
| 能量确定性 | 时间全部由入参 `now` 驱动 | Core 纯函数式，`EnergyEngine` 完全可单测 |
| 构建系统 | SwiftPM（非裸 xcodebuild） | 无头可自动化验证；`swift test` 直接跑通 |

`Stop` 的语义是「一轮回合结束」而非「整个长任务结束」，MVP 明确按回合计一次完成（RFC R3 已记录，后续观察是否需要合并短回合）。

## 4. 踩坑记录

- **`JSONSerialization` 会把 `/` 转义成 `\/`**：导致注入 hook 后按原始路径子串匹配失败（idempotent 测试一度红）。修复：写文件前把 `\/` 还原为 `/`——既过测试，也让用户的 `settings.json` 更干净、与 Claude Code 自身写法一致。
- **`swift-format` 默认 2 空格缩进 / 100 列**：与 Xcode 默认 4 空格冲突，刷屏告警。修复：加项目级 `.swift-format`（4 空格 / 120 列），再 `format -i` 归一，最终 0 warning。
- **Codable 字段的蛇形命名触发 `AlwaysUseLowerCamelCase`**：用 `CodingKeys` 把 `hook_event_name` 等映射到 camelCase 属性即可。
- **SwiftPM 校验所有 target 路径必须存在**：只写了 Core 就跑 `swift test` 会因 `Sources/App` 不存在而报错——得先把 App/Hook 目录建好。
- **无图形会话跑 GUI**：菜单栏 App 无法在无头环境渲染。用 `--selftest` 子命令无 GUI 地跑通「摄取→计数→能量」链路，作为可自动化的端到端验证。
- **XCUITest 需真 `.xcodeproj` + GUI**（补 Step 9 时踩到）：SwiftPM 承载不了 UI 测试 target，用 xcodegen 从 `project.yml` 生成工程；`菜单栏 NSStatusItem 不可被 XCUITest 寻址`，只能测宠物窗 `NSPanel`。本地无头 shell 跑 XCUITest 会在 bootstrap 被 kill，只能到「编译级」，真正运行交给 CI。
- **xcodegen 生成的工程 `objectVersion 77`（Xcode 16 格式）**：GitHub runner 默认 Xcode 15.4 读不了（`Unable to read project`）。修复：uitest job 用 `setup-xcode@latest-stable`（拿到 Xcode 16.2）。

## 5. 验证结果

- `swift test`：**45 用例全通过**（能量引擎 / 任务态机 / spool 摄取 / hook 注入回滚 / 持久化 / 编排）。
- `swift-format lint`：**0 warning**。
- `swift build`：通过；`agentmon --selftest` → `completed=1 working=0 energy=30 level=1 -> OK`。
- `agentmon-hook` 真实烟测：stdin JSON → 正确原子写出 spool 文件。
- **XCUITest E2E（Step 9，CI 上 Xcode 16.2）**：`agentmonUITests` **2 用例全通过**（`testPetShowsWorking` / `testPetReturnsToIdleAfterCompletion`）——真实 spool → pump → 宠物窗状态链路验证通过。
- **CI（GitHub Actions）**：`check` / `uitest` / `package` 三 job 全绿。

## 6. 可复用经验

1. **把纯逻辑从 UI/IO 里挤出来**：时间用入参而非 `Date()`，Core 就能 100% 确定性单测——这是让 TDD 真正跑起来的关键。
2. **本地进程间通信优先考虑 drop-file spool**：比起 socket/HTTP，它免端口、可持久化、易测试，非常适合「hook → 常驻 App」这类场景。
3. **动用户配置务必：先备份、可幂等、可精确回滚、损坏即中止**。这是能让用户放心「启用集成」的底线。
4. **养成类数值要单调激励**：进化不回退，坏日子只停滞——正反馈比惩罚更能拉长专注时段。
5. **工具链先探测再定命令**：本机 `swiftlint` 缺失但 `swift-format` 经 `xcrun` 可用，据此把工作流命令改到实际能跑的那套，别让 AGENTS.md 写着跑不通的命令。
