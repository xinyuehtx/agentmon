# RFC: agentmon Agent 任务监控 MVP

- **Slug**: `agent-task-monitor`
- **状态**: Draft（待审阅）
- **作者**: agentmon team
- **日期**: 2026-07-23

---

## 1. 背景

开发者常同时开着多个 Agent 客户端（Claude Code、Qoder、QoderWorker、Codex 等）跑长任务，任务何时在跑、何时卡在等待、何时结束缺乏统一、直观的感知，容易「以为在跑其实卡住」或「跑完了没及时接手」。

agentmon 用一只 AI 原创小猫做「养成式」监控：把散落在各客户端的任务态汇聚成菜单栏计数 + 桌面宠物，用能量/进化机制把「保持健康的工作节奏」变成正反馈。

## 2. 目标 / 非目标

### 2.1 目标（MVP）
1. 监控 Agent 长任务的三种态：**启动（工作中）/ 暂停（等待中）/ 结束（已完成）**。
2. **菜单栏**展示每个客户端「工作中 / 等待中 / 已完成」任务数量。
3. **桌面宠物浮窗**：小猫按任务态积累/消耗能量，能量达门槛触发**进化（换肤）**，支持基本互动。
4. **Claude Code 适配器做完整**（hooks 驱动，精确态）；Qoder/QoderWorker/Codex 提供**适配器骨架 + 配置位**（进程/日志探测，尽力而为），保证架构可扩展。
5. 能量与进化门槛可配置，默认值经设计使「合理工作强度」可在可预期时间内完成首次进化。

### 2.2 非目标（MVP 不做）
- 不干预/暂停/杀死任何 Agent（**只读监控**）。
- 不在首版把 Qoder/QoderWorker/Codex 做到生产级可靠（仅骨架）。
- 不做 WidgetKit 桌面小组件（用浮窗宠物替代，理由见 §5）。
- 不做云同步、多用户、跨平台（Windows/Linux）。
- 不做任务内容/隐私数据的采集与上传（事件仅本地处理）。

## 3. 术语与状态定义

| 术语 | 定义 |
| --- | --- |
| 会话(session) | 一个客户端实例内的一次交互上下文（如一个 Claude Code 会话） |
| 任务(task) | 一次「用户发起 → Agent 处理 → 结束」的长任务回合 |
| 工作中(working) | Agent 正在处理（生成/调用工具） |
| 等待中(waiting) | Agent 暂停等待用户输入/授权/确认 |
| 已完成(completed) | 一次任务回合结束（累计计数） |
| 空闲(idle) | 无进行中的任务 |

**任务态机**：`idle → (启动) working → (暂停) waiting → (继续) working → (结束) completed → idle`

## 4. 详细方案

### 4.1 总体架构

```
┌────────────────────────── agentmon.app (Swift) ──────────────────────────┐
│                                                                            │
│  采集层 Adapters            状态引擎 Core            展示层 UI              │
│  ┌───────────────┐         ┌────────────────┐      ┌──────────────────┐   │
│  │ ClaudeAdapter │──event─▶│ TaskStore      │─────▶│ MenuBar (MenuBarExtra) │
│  │ (hooks/spool) │         │ (per-client 计数)│      └──────────────────┘   │
│  ├───────────────┤         │ EnergyEngine   │      ┌──────────────────┐   │
│  │ Codex/Qoder   │──event─▶│ (能量/进化)     │─────▶│ PetPanel (NSPanel)│   │
│  │ (骨架:进程/日志)│         └───────┬────────┘      └──────────────────┘   │
│  └───────────────┘                 │                                       │
│                              持久化 Persistence (Application Support/*.json)│
└────────────────────────────────────────────────────────────────────────┘
```

### 4.2 技术栈与工程结构
- **语言/框架**：Swift + SwiftUI + AppKit，最低 macOS 13（`MenuBarExtra` 可用）。
- **工程形态**：Xcode 工程（需 app bundle、代码签名、后续 XCUITest / 可能的 WidgetKit 扩展）。
  - `agentmon`（主 App target，`LSUIElement=true` 无 Dock 图标）
  - `agentmonCore`（可测的纯逻辑 framework/target：TaskStore、EnergyEngine、事件模型、适配器协议）
  - `agentmonTests`（单元）、`agentmonUITests`（XCUITest）
- **依赖**：优先零三方依赖；`swiftlint` / `swift-format` 作为开发工具（brew 安装，不入包）。
- **建议目录**：
  ```
  agentmon.xcodeproj
  Sources/
    App/            # @main, MenuBarExtra, PetPanel
    Core/           # TaskStore, EnergyEngine, Models, AdapterProtocol
    Adapters/       # ClaudeAdapter, (Codex/Qoder 骨架)
    Assets/         # 原创小猫资源 + 皮肤
  Tests/ (unit) · UITests/
  ```

### 4.3 采集层：Claude Code 适配器（参考实现）

**信号来源：Claude Code hooks**。agentmon 提供「启用 Claude Code 集成」动作，向 `~/.claude/settings.json` **合并写入**（写前备份）以下 hooks，指向一个随 App 分发的上报脚本 `agentmon-hook`：

| Claude hook 事件 | 语义映射 |
| --- | --- |
| `UserPromptSubmit` | 任务**启动** → 该会话置 working |
| `Notification` | Agent 需要输入/授权 → **暂停** → waiting |
| `Stop` | 任务回合**结束** → completed（+能量），会话回 idle |
| `SessionStart` / `SessionEnd` | 维护会话生命周期（清理计数） |

**传输：drop-file spool（无网络、无端口、原子、可断点续传）**
- `agentmon-hook` 从 stdin 读取 hook 的 JSON，附加接收时间戳，**写临时文件再 `rename`** 到
  `~/Library/Application Support/agentmon/spool/<uuid>.json`（rename 原子，避免半写）。
- App 用 `FSEvents`/`DispatchSource` 监听 spool 目录，读取→入引擎→删除；App 未运行时事件在磁盘排队，启动后补消费。
- 选型理由：相比 localhost HTTP/UDS，drop-file 免端口冲突、进程隔离、天然持久化，最易测试；实时性（<1s）满足需求。

**卸载/回滚**：「停用集成」动作从 `~/.claude/settings.json` 精确移除 agentmon 注入的 hook 项（用标记块/可识别命令定位），恢复备份。

### 4.4 采集层：其他客户端（MVP 仅骨架）
- 定义统一 `AgentAdapter` 协议（`start()/stop()`，产出标准 `TaskEvent`）。
- Codex/Qoder/QoderWorker 提供**进程探测（是否运行）+ 日志目录监听**骨架与配置位；**确切日志路径与状态标记留待后续需求实测**，MVP 不保证其 working/waiting 精度。
- 未识别客户端在菜单栏可显示「运行中(进程存在)」但不参与能量结算（避免噪声污染养成）。

### 4.5 事件模型与状态机

```swift
enum TaskState { case working, waiting, completed }
struct TaskEvent {
  let client: String        // "Claude Code"
  let sessionID: String
  let kind: Kind            // .start / .pause / .resume / .end
  let timestamp: Date
}
```
`TaskStore` 维护 `sessionID → 当前态`，派生每客户端的 `working/waiting` 计数与全局 `completed` 累计计数。幂等：重复/乱序事件按 timestamp 归并，`end` 幂等（同会话重复 end 只记一次完成）。

### 4.6 能量与进化模型

**两个概念分离**：
- `energy`：当前能量，随任务态实时涨落，驱动小猫情绪动画，并向下一级进度累积。
- `level`：进化阶段，**单调不回退**（养成不惩罚，避免掉级劝退）。

**速率（默认值，均可配置）**
| 事件 | 能量变化 |
| --- | --- |
| 每个工作中任务 | `+2 / 分钟` |
| 每个等待中任务 | `−1 / 分钟` |
| 每次任务完成 | `+30`（一次性） |
| 无任务（空闲衰减） | `−0.5 / 分钟` |

- 引擎每 **60s tick** 一次，按当前各态任务数结算；`energy` 下限 0（坏日子只暂停进度、不掉级）。
- **进化**：当 `energy ≥ T(level)` 时 `level += 1`，`energy -= T(level_old)`（余量结转），触发换肤动画。

**门槛曲线（默认）**
| 跃迁 | 累计能量门槛 | 直觉耗时（合理强度*） |
| --- | --- | --- |
| Lv1 → Lv2 | 300 | 约半个专注工作日（首次进化快，早正反馈） |
| Lv2 → Lv3 | 900 | 约 2–3 天 |
| Lv3 → Lv4 | 2000 | 约 1 周 |

\* 估算基准：单任务工作中约 `+120/h`，日均完成 3–6 次约 `+90~180`；一次 ~4h 专注工作日净增约 `+500`。故 Lv2 首日可达、后续阶梯递增。全部数值在 `config.json` 可调以便灰度调参。

**MVP 交付范围**：引擎支持任意 N 级与门槛；美术上至少交付 **Lv1 基础形态 + Lv2 进化形态**（2 套皮肤），验证「进化换肤」链路端到端可用。

### 4.7 展示层：菜单栏（MenuBarExtra）
- 状态栏图标 = 小猫头像 + 紧凑摘要，如 `▶3 ⏸1 ✓12`（工作中/等待中/已完成）。
- 下拉：按客户端分组的三态计数、当前能量条与等级、「显示/隐藏宠物」「启用/停用 Claude 集成」「设置」「退出」。

### 4.8 展示层：桌面宠物浮窗（NSPanel）
- 无边框、透明、`.floating` 常驻置顶、`nonactivatingPanel`（点击不抢焦点）、可拖拽、支持多屏。
- 状态驱动动画：working=精神/劳作；waiting/idle=犯困/饥饿；completed=庆祝迸发；level up=进化演出。
- 互动（MVP）：拖动移动位置、点击「撸猫」触发反应；hover 显示能量/等级。喂食等留后续。

### 4.9 美术资源（AI 原创小猫）
- 形象：一只 AI 原创小猫（非任何既有 IP）。
- **MVP 实现**：以程序化矢量（SVG/SwiftUI Shape）绘制原创小猫，皮肤 = 配色/配饰切换，保证无需外部素材即可构建与进化演示；
- **后续**：用图像模型产出高保真精灵图集（sprite sheet）替换，皮肤对应进化阶段。资源与授权作为独立任务跟踪。

### 4.10 持久化与配置
- `~/Library/Application Support/agentmon/`
  - `state.json`：energy、level、completed 累计、各会话态快照、最近 tick 时间（用于重启补算）。
  - `config.json`：能量速率、门槛曲线、启用的客户端、spool 路径。
  - `spool/`：事件投递目录。
- 重启恢复：加载 state，按 `now − 最近tick` 补算离线期间的空闲衰减（离线不计工作能量）。
- 可选：登录启动（`SMAppService`）。

## 5. 备选方案对比

| 维度 | **本方案：原生 Swift（选定）** | Tauri/Electron | WidgetKit 做宠物 |
| --- | --- | --- | --- |
| 菜单栏 | `MenuBarExtra` 最原生 | Tray 可行 | 不适用 |
| 桌面宠物 | NSPanel 流畅、可互动 | 透明窗可行、略重 | ❌ 无法承载连续动画/实时互动 |
| 采集 | FSEvents + hooks | Node 侧 | 受限 |
| 资源占用 | 最低 | 中/高 | 低 |
| 与 pnpm 工作流一致 | ❌（已改 AGENTS.md 为 Swift 链） | ✅ | 部分 |

**结论**：用户选定原生 Swift；宠物用 **NSPanel 浮窗**（而非 WidgetKit），因 WidgetKit 无法满足连续动画与实时互动需求。WidgetKit 可作后续「一眼看计数」的补充扩展。

## 6. 迁移与回滚
- 新仓库，无历史数据迁移。
- **安装即迁移**：分发 notarized `.app`。
- **回滚**：
  1. 「停用 Claude 集成」→ 从 `~/.claude/settings.json` 移除注入 hooks（写入前已备份）。
  2. 退出并删除 `agentmon.app` 与 `~/Library/Application Support/agentmon/`。
- **关键约束**：任何对用户 `~/.claude/settings.json` 的写入都必须**先备份、可精确撤销、幂等**（不重复注入、不破坏用户既有 hooks）。

## 7. 灰度策略
- 适配器级开关：Claude 默认开，其余默认关（骨架）。
- 能量/门槛全部走 `config.json`，无需重编译即可调参灰度。
- 发布阶梯：本机 dogfood → 内部 notarized DMG → 更大范围 GA。

## 8. 验收标准（Given/When/Then）
1. **启动**：Given 已启用 Claude 集成，When Claude 提交任务（`UserPromptSubmit`），Then ≤2s 内该客户端「工作中」+1，宠物进入 working 动画。
2. **暂停**：When Claude 触发 `Notification`（等待输入/授权），Then 该会话转 waiting，「等待中」计数反映。
3. **结束**：When Claude `Stop`，Then「已完成」累计 +1，能量 +30，宠物播放庆祝。
4. **能量/进化**：按默认速率累积，When `energy` 跨过 Lv1→Lv2 门槛，Then 触发进化换肤且 `level` 持久化、不回退。
5. **持久化**：重启 App 后 energy/level/计数恢复，离线期仅结算空闲衰减。
6. **回滚**：停用集成后 `~/.claude/settings.json` 不再含 agentmon hooks，用户原有配置完好。
7. **测试**：EnergyEngine 与 事件→态 映射有单元测试；spool 摄取有集成测试；菜单栏 + 宠物窗有 XCUITest 冒烟。

## 9. 里程碑 / 工作量（MVP，中等量级）
1. 工程骨架 + Core 模型 + 单测脚手架
2. ClaudeAdapter（hooks 注入/回滚 + spool 摄取）
3. TaskStore + EnergyEngine（+ 单测）
4. 菜单栏 UI
5. 宠物浮窗 + 原创小猫(Lv1) + 1 次进化(Lv2)
6. 持久化 + 配置 + 回滚
7. XCUITest 冒烟 + 验证报告

## 10. 风险与未决问题
- **R1 非 Claude 客户端状态精度**：Codex/Qoder 日志格式未知 → MVP 仅骨架，风险隔离。
- **R2 写用户 `~/.claude/settings.json`**：需严格备份/幂等/可撤销（见 §6）。
- **R3 hook「结束」语义**：`Stop` 是「一轮回合结束」，与「用户心智里的整个长任务结束」可能不完全一致 → SPEC 阶段明确按「回合」计一次完成，并观察是否需要合并短回合。
- **R4 透明置顶窗**在全屏/多屏/Mission Control 下行为 → 实现期实测。
- **R5 门槛调参**：默认曲线需 dogfood 校准，故全部可配置。
- **未决**：是否 MVP 就提供 WidgetKit 计数小组件（暂定否）；登录启动是否默认开启（暂定否，用户手动开）。
