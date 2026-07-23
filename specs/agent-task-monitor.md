# SPEC: agentmon Agent 任务监控 MVP

- **Slug**: `agent-task-monitor`
- **对应 RFC**: [`rfcs/agent-task-monitor.md`](../rfcs/agent-task-monitor.md)
- **状态**: Draft（随 Story/测试一并提交 Step 6 审查）

本 SPEC 细化到可指导实现，但不含具体实现代码。所有类型/方法签名为**接口契约**，实现须与之一致（测试按此编写）。

---

## 0. 模块总览

```
agentmonCore (可测纯逻辑, 无 UI/无 IO 依赖)
├── Models          TaskEvent / TaskEventKind / ClientCounts / EvolutionEvent
├── TaskStore       事件 → 每客户端三态计数
├── EnergyEngine    时间/事件 → 能量与进化(level)
├── EnergyConfig    速率与门槛(可配置)
├── ClaudeEventMapper  Claude hook 名 → TaskEvent
├── SpoolIngestor   spool 目录 → [TaskEvent]（读入即删）
├── ClaudeHookInstaller  ~/.claude/settings.json 注入/回滚
└── StateStore      state.json / config.json 读写

agentmon (App, 依赖 Core)
├── AppCoordinator  组合 Core + 定时 tick + 适配器生命周期
├── MenuBarView     MenuBarExtra
└── PetPanel        NSPanel 宠物浮窗
```

**分层原则**：`agentmonCore` 不 import AppKit/SwiftUI、不做 `Date()`（时间由入参传入），保证纯函数式可测；IO（文件/FSEvents）封装在薄封装层，Core 只接收已解析的数据结构。

---

## 1. 数据模型（Models）

```swift
public enum TaskEventKind: String, Codable, Equatable {
    case start   // 任务启动 / 从等待恢复 → working
    case pause   // 等待用户输入/授权 → waiting
    case end     // 任务回合结束 → completed，会话回 idle
}

public struct TaskEvent: Equatable {
    public let client: String      // 例 "Claude Code"
    public let sessionID: String   // 客户端会话 ID
    public let kind: TaskEventKind
    public let timestamp: Date
    public init(client: String, sessionID: String, kind: TaskEventKind, timestamp: Date)
}

public struct ClientCounts: Equatable {
    public var working: Int
    public var waiting: Int
    public var completed: Int      // 累计完成数（不清零）
    public init(working: Int, waiting: Int, completed: Int)
}

public struct EvolutionEvent: Equatable {
    public let newLevel: Int
}
```

**会话内部态**（不对外暴露）：`enum SessionState { case working, waiting, idle }`。

---

## 2. TaskStore —— 事件到三态计数

### 2.1 契约
```swift
public final class TaskStore {
    public init()
    public func apply(_ event: TaskEvent)
    public func counts(for client: String) -> ClientCounts
    public func allClients() -> [String]        // 出现过的客户端（有序去重）
    public var totalWorking: Int { get }         // 跨客户端工作中会话数
    public var totalWaiting: Int { get }
    public var totalCompleted: Int { get }
}
```

### 2.2 内部状态
- `sessions: [Key: (state: SessionState, lastTS: Date)]`，`Key = client + "\u{1}" + sessionID`（按客户端命名空间隔离，避免不同客户端 sessionID 撞车）。
- `completedByClient: [String: Int]`
- `clientOrder: [String]`（首次出现顺序）

### 2.3 状态机（每会话）
| 当前态 \ 事件 | start | pause | end |
| --- | --- | --- | --- |
| idle/未知 | → working | → waiting | 忽略（幂等，不计完成） |
| working | → working | → waiting | → idle，completed++ |
| waiting | → working | → waiting | → idle，completed++ |

### 2.4 规则（异常/边界）
1. **陈旧事件守卫**：若 `event.timestamp < sessions[key].lastTS`，整条忽略（乱序保护）。否则更新 `lastTS`。
2. **end 幂等**：仅当会话处于 working/waiting 才计一次 completed 并转 idle；对 idle/未知会话的 end 不增计数。
3. **首见客户端**：任何事件首次出现即登记到 `clientOrder` 与 `completedByClient[client]=0`。
4. `counts(for:)` 对未知客户端返回全 0。
5. `working/waiting` 为**当前活跃会话数**（派生量）；`completed` 为**累计计数**。

### 2.5 数据流
`SpoolIngestor.drain()` → `[TaskEvent]`（按 timestamp 升序）→ 逐条 `TaskStore.apply` → UI 读取 `counts/total*`。

---

## 3. EnergyConfig —— 可配置速率与门槛

```swift
public struct EnergyConfig: Codable, Equatable {
    public var workingPerMin: Double    // 默认 +2   （每个工作中任务/分钟）
    public var waitingPerMin: Double    // 默认 -1   （每个等待中任务/分钟）
    public var completedBonus: Double   // 默认 +30  （每次完成一次性）
    public var idleDecayPerMin: Double  // 默认 -0.5 （无任务时/分钟）
    public var thresholds: [Double]     // 默认 [300, 900, 2000]
    public static let `default`: EnergyConfig
}
```

**门槛语义**：`thresholds[i]` = 从 `level=(i+1)` 升到 `(i+2)` 所需能量。
```swift
func threshold(forLevel level: Int) -> Double
// level ∈ [1, thresholds.count]  → thresholds[level-1]
// level >  thresholds.count      → thresholds.last! * pow(2, level - thresholds.count)
// 默认: t(1)=300, t(2)=900, t(3)=2000, t(4)=4000, t(5)=8000 ...
```

---

## 4. EnergyEngine —— 能量与进化

### 4.1 契约
```swift
public final class EnergyEngine {
    public private(set) var energy: Double
    public private(set) var level: Int          // 从 1 起，单调不回退
    public let config: EnergyConfig
    public var onEvolve: ((EvolutionEvent) -> Void)?

    public init(config: EnergyConfig = .default,
                energy: Double = 0,
                level: Int = 1,
                lastTick: Date)

    public func tick(now: Date, workingCount: Int, waitingCount: Int)
    public func registerCompletions(_ count: Int, now: Date)
    public func applyOfflineDecay(now: Date)
    public func threshold(forLevel level: Int) -> Double
}
```

### 4.2 计算规则
- 内部维护 `lastTick: Date`。`elapsedMin(now) = max(0, (now - lastTick)/60)`。
- **tick**：
  ```
  if workingCount > 0 || waitingCount > 0:
      delta = (workingPerMin*workingCount + waitingPerMin*waitingCount) * elapsedMin
  else:
      delta = idleDecayPerMin * elapsedMin        // 空闲衰减
  energy = max(0, energy + delta)                 // 能量下限 0
  lastTick = now
  checkEvolution()
  ```
- **registerCompletions(n)**：`energy = max(0, energy + completedBonus*n)`；`checkEvolution()`。（不改 lastTick）
- **applyOfflineDecay(now)**：整段按空闲衰减 `energy = max(0, energy + idleDecayPerMin*elapsedMin)`；`lastTick=now`；不升级。
- **checkEvolution**：
  ```
  while energy >= threshold(forLevel: level):
      energy -= threshold(forLevel: level)
      level  += 1
      onEvolve?(EvolutionEvent(newLevel: level))   // 支持一次跨多级，逐级回调
  ```

### 4.3 不变量
- `energy >= 0` 恒成立。
- `level` 只增不减（坏日子仅停滞进度）。
- 相同输入序列 → 相同结果（纯确定性，`now` 全部由入参驱动）。

### 4.4 默认门槛的设计依据（可 dogfood 调参）
单任务工作中 ≈ `+120/h`；日均完成 3–6 次 ≈ `+90~180`；一次 ~4h 专注日净增 ≈ `+500`。
→ Lv2=300（首日可达，早正反馈）、Lv3=900（2–3 天）、Lv4=2000（约 1 周）。

---

## 5. 采集层

### 5.1 ClaudeEventMapper
```swift
public enum ClaudeEventMapper {
    // 返回 nil 表示该 hook 事件不参与三态（如 SessionStart/PreToolUse）
    public static func map(hookEventName: String,
                           client: String,
                           sessionID: String,
                           timestamp: Date) -> TaskEvent?
}
```
| hookEventName | → kind |
| --- | --- |
| `UserPromptSubmit` | `.start` |
| `Notification` | `.pause` |
| `Stop` | `.end` |
| 其他（`SessionStart`/`PreToolUse`/…） | `nil` |

### 5.2 Spool 文件格式（`agentmon-hook` 写入）
- 目录：`~/Library/Application Support/agentmon/spool/`
- 文件：`<uuid>.json`，**先写 `<uuid>.json.tmp` 再 `rename`**（原子）。
- 内容：
  ```json
  {
    "hook_event_name": "Stop",
    "session_id": "abc-123",
    "client": "Claude Code",
    "received_at": "2026-07-23T10:00:00Z"
  }
  ```

### 5.3 SpoolIngestor
```swift
public final class SpoolIngestor {
    public init(directory: URL)
    /// 读取目录内所有 *.json（忽略 *.tmp），解析→映射→按 timestamp 升序返回；
    /// 每个成功读取的文件在返回前删除（无论是否映射出事件）。
    /// 解析失败的单个文件：记录日志、删除、跳过（不影响其它文件）。
    public func drain() throws -> [TaskEvent]
}
```
- 数据流：`FSEvents 监听 spool/` → `drain()` → `[TaskEvent]` → `TaskStore.apply`。
- App 启动时先 `drain()` 一次消费离线期间堆积事件。

### 5.4 ClaudeHookInstaller —— 写用户 settings.json（可回滚）
```swift
public final class ClaudeHookInstaller {
    public init(settingsURL: URL, reporterCommand: String)
    public func install() throws     // 合并注入；先备份；幂等
    public func uninstall() throws   // 仅移除 agentmon 注入项；恢复保留用户项
    public func isInstalled() throws -> Bool
}
```
- **注入位置**：`settings.json` → `hooks.<Event>[]`。**MVP 注入恰好 3 个事件**：`UserPromptSubmit`、`Notification`、`Stop`（会话清理用的 `SessionEnd` 留待后续需求）。
- **可识别标记**：注入的 command 统一为 `reporterCommand`（内部含 `agentmon-hook` 标识串），据此定位 agentmon 项，避免误删用户 hooks。
- **备份**：install 前将原文件复制到 `settings.json.agentmon.bak`。
- **幂等**：重复 install 不产生重复项（按标记去重）。
- **合并**：保留用户已有的其它 hooks 与非 hooks 字段不变。
- **不存在文件**：视为无 hooks，创建最小合法结构后注入。
- **JSON 损坏**：抛错，不写入（避免破坏用户配置）。

---

## 6. 持久化（StateStore）

```swift
public struct PersistentState: Codable, Equatable {
    public var energy: Double
    public var level: Int
    public var completedByClient: [String: Int]
    public var lastTick: Date
}

public final class StateStore {
    public init(stateURL: URL, configURL: URL)
    public func loadState() throws -> PersistentState?   // 无文件返回 nil
    public func saveState(_ s: PersistentState) throws    // 原子写(temp+rename)
    public func loadConfig() throws -> EnergyConfig        // 无文件返回 .default
    public func saveConfig(_ c: EnergyConfig) throws
}
```
- 目录：`~/Library/Application Support/agentmon/`（`state.json` / `config.json`）。
- 启动恢复：`loadState` → 用 `lastTick` 调 `EnergyEngine.applyOfflineDecay(now)`（离线只衰减，不计工作能量）。
- 保存时机：每次 tick 后、每次进化后、退出前；原子写避免半文件。

---

## 7. App 编排（AppCoordinator）

- 组合：`TaskStore` + `EnergyEngine` + `SpoolIngestor` + `ClaudeHookInstaller` + `StateStore`。
- **主循环**：`Timer` 每 60s → `ingestor.drain()` → 逐条 `store.apply` → 统计本 tick 内 `end` 次数 → `engine.registerCompletions(n)` → `engine.tick(now, store.totalWorking, store.totalWaiting)` → 刷新 UI → `saveState`。
- FSEvents 触发时可提前 drain（低延迟），但能量结算仍按 tick 周期，保证时间口径一致。
- 生命周期：启动时 `loadConfig/loadState` → `applyOfflineDecay` → 首次 `drain`；退出时 `saveState`。

## 8. 展示层

### 8.1 MenuBarView（MenuBarExtra）
- 标题：猫头像 + `▶{totalWorking} ⏸{totalWaiting} ✓{totalCompleted}`。
- 菜单：按 `allClients()` 分组显示各 `ClientCounts`；能量条 + `Lv{level}`；开关「显示宠物」「启用/停用 Claude 集成」「设置…」「退出」。
- 数据只读自 Core，不反向写。

### 8.2 PetPanel（NSPanel）
- `styleMask=[.borderless, .nonactivatingPanel]`，`level=.floating`，`isOpaque=false`，`backgroundColor=.clear`，`collectionBehavior=[.canJoinAllSpaces, .stationary]`，可拖拽。
- 状态→动画：`totalWorking>0`→working；`totalWaiting>0 且 working==0`→waiting；均为 0→idle；收到 `end`→celebrate；`onEvolve`→evolve 演出并切皮肤到 `level`。
- 互动：拖动移动；点击触发「撸猫」反应；hover 显示 energy/level。

### 8.3 美术资源
- Lv1 基础形态 + Lv2 进化形态（矢量，皮肤=配色/配饰切换）；资源置于 `Sources/Assets/`，以 `level` 索引。

## 9. 日志与「埋点」（本地，不上传）
- 用 `os.Logger`（subsystem `com.agentmon`）：categories `adapter`/`engine`/`ui`/`persistence`。
- 记录：事件摄取条数、进化发生（旧→新 level）、hook 安装/卸载结果、解析失败文件。
- **隐私**：不记录任务/提示内容；spool 仅取 `hook_event_name/session_id/client/received_at`；无任何网络请求。

## 10. 异常分支汇总
| 场景 | 处理 |
| --- | --- |
| spool 文件 JSON 损坏 | 记日志、删文件、跳过 |
| 未知 hook 事件 | 映射 nil、删文件、不计数 |
| 乱序事件 | timestamp 守卫忽略陈旧 |
| 重复 end | 幂等，不重复计完成 |
| 能量将为负 | 截断到 0 |
| settings.json 损坏 | install 抛错，不写入 |
| 重复 install | 幂等，不重复注入 |
| App 离线一段时间 | 启动按 lastTick 施加空闲衰减 |
| 未知客户端进程 | 菜单可显示但不参与能量结算 |

## 11. 测试映射（详见 `tests/`）
- 单元：`EnergyEngineTests`（累积/惩罚/完成/衰减/floor/进化/多级跳/不回退/门槛函数）、`TaskStoreTests`（三态/幂等 end/多客户端隔离/多会话/陈旧守卫/恢复）。
- 集成：`SpoolIngestionTests`（Claude hook JSON→事件→计数、损坏跳过、读入即删）、`ClaudeHookInstallerTests`（合并注入/备份/幂等/精确卸载/损坏保护）。
- E2E（Step 9，XCUITest）：见 `tests/e2e/README.md`。
