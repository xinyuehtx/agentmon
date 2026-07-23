# User Stories: agentmon Agent 任务监控 MVP

- **Slug**: `agent-task-monitor`
- **对应**: [`rfcs/agent-task-monitor.md`](../rfcs/agent-task-monitor.md) · [`specs/agent-task-monitor.md`](../specs/agent-task-monitor.md)

覆盖正向、失败/删除、边界三类场景。验收标准用 Given / When / Then。

---

## Epic A：任务态监控与菜单栏

### US-A1 看到工作中任务（正向）
**As a** 同时跑多个 Agent 的开发者
**I want** 菜单栏实时显示各客户端「工作中」任务数
**So that** 我一眼知道谁在忙

- **Given** 已启用 Claude Code 集成
- **When** 我在 Claude Code 提交一个任务（触发 `UserPromptSubmit`）
- **Then** ≤2s 内菜单栏该客户端「工作中」+1，宠物进入 working 状态

### US-A2 看到等待中任务（正向）
**As a** 开发者
**I want** 知道哪个 Agent 卡在等待我输入/授权
**So that** 我能及时接手，不让它空等

- **Given** 某 Claude 会话正在工作中
- **When** 它触发 `Notification`（需要输入/授权）
- **Then** 该会话从「工作中」转为「等待中」，两个计数同步更新

### US-A3 看到已完成任务累计（正向）
**As a** 开发者
**I want** 看到已完成任务的累计数
**So that** 我对今天的产出有感知

- **Given** 某 Claude 会话工作中或等待中
- **When** 它触发 `Stop`（回合结束）
- **Then** 该客户端「已完成」累计 +1，会话回 idle，宠物播放庆祝

### US-A4 多客户端分组（边界）
**As a** 同时用 Claude 与其他客户端的开发者
**I want** 计数按客户端分组、互不串扰
**So that** 我能区分是谁的任务

- **Given** Claude 有 1 个工作中会话，另一客户端有 1 个工作中会话
- **When** 我查看菜单栏
- **Then** 两客户端各自显示 working=1，全局 totalWorking=2
- **And** 结束其中一个客户端的会话不影响另一个的计数

### US-A5 未知客户端进程（边界）
**As a** 开发者
**I want** 未接入精确适配的客户端至少能显示「运行中」
**So that** 我知道它开着，但不干扰养成数据

- **Given** 一个仅有进程探测的客户端在运行
- **When** 我查看菜单栏
- **Then** 可显示其「运行中」，但它**不参与能量结算**

---

## Epic B：能量与进化（宠物养成）

### US-B1 工作积累能量（正向）
**As a** 用户
**I want** 保持任务工作中时宠物能量缓慢上涨
**So that** 专注工作能推动养成

- **Given** 能量 E、1 个工作中任务、无等待
- **When** 经过 10 分钟 tick
- **Then** 能量 = E + 2×1×10 = E+20

### US-B2 等待消耗能量（正向/失败向）
- **Given** 能量 E、0 工作中、2 个等待中
- **When** 经过 10 分钟
- **Then** 能量 = E + (−1×2)×10 = E−20

### US-B3 完成大幅加能（正向）
- **Given** 能量 E
- **When** 一次任务完成（`end`）
- **Then** 能量 = E + 30（一次性）

### US-B4 无任务缓慢衰减（边界）
- **Given** 能量 E、无任何工作中/等待中任务
- **When** 经过 10 分钟
- **Then** 能量 = E + (−0.5×10) = E−5

### US-B5 能量不为负（边界）
- **Given** 能量 3、无任务
- **When** 经过 10 分钟（应扣 5）
- **Then** 能量截断为 0（不出现负值）

### US-B6 达门槛触发进化（正向）
**As a** 用户
**I want** 能量累计到门槛时宠物进化换肤
**So that** 我获得成长的正反馈

- **Given** 默认门槛（Lv1→Lv2=300），当前 level=1、能量=290
- **When** 完成一次任务（+30 → 320）
- **Then** level 升到 2，能量结转为 20，宠物播放进化并切换到 Lv2 皮肤

### US-B7 进化不回退（失败向/边界）
**As a** 用户
**I want** 即使能量掉光也不掉级
**So that** 坏日子不会让我前功尽弃

- **Given** 已进化到 level=2
- **When** 长时间无任务导致能量衰减到 0
- **Then** 能量为 0 但 level 仍为 2（不回退到 1）

### US-B8 一次跨多级（边界）
- **Given** level=1、能量=0，默认门槛 [300,900,2000]
- **When** 一次结算净增 1300 能量
- **Then** 依次升到 level=3、能量=100，进化回调对 Lv2、Lv3 各触发一次

### US-B9 离线衰减（边界）
**As a** 用户
**I want** 重开 App 后能量按离线时长合理衰减、等级与计数恢复
**So that** 数据连续可信

- **Given** 关闭 App 前能量=100、level=2、lastTick=T
- **When** 60 分钟后重新打开 App
- **Then** 按空闲衰减能量=70，level=2，累计完成数不丢失

---

## Epic C：Claude 集成的启用与回滚

### US-C1 一键启用集成（正向）
**As a** 用户
**I want** 一键把 agentmon 的 hooks 装进 Claude Code
**So that** 我不用手改配置

- **Given** 我的 `~/.claude/settings.json` 已有我自己的 hooks
- **When** 我点击「启用 Claude 集成」
- **Then** 注入 agentmon 的 UserPromptSubmit/Notification/Stop hooks，**保留**我原有 hooks，并生成备份 `settings.json.agentmon.bak`

### US-C2 幂等启用（边界）
- **Given** 已启用过集成
- **When** 我再次点击「启用」
- **Then** 不产生重复 hook 项（幂等）

### US-C3 一键回滚（删除/失败向）
**As a** 用户
**I want** 停用集成时干净移除 agentmon 的改动
**So that** 我能放心卸载

- **Given** 已启用集成且我有自己的 hooks
- **When** 我点击「停用 Claude 集成」
- **Then** 仅移除 agentmon 注入的 hook 项，我原有 hooks 与其它配置完好，`isInstalled()` 为 false

### US-C4 配置损坏保护（失败向）
- **Given** `~/.claude/settings.json` 是损坏的非法 JSON
- **When** 我点击「启用集成」
- **Then** 操作报错并中止，**不写入/不破坏**原文件

---

## Epic D：事件摄取健壮性

### US-D1 正常摄取（正向）
- **Given** spool 目录有一个合法的 Claude `Stop` 事件文件
- **When** 摄取器 `drain()`
- **Then** 产出一个 `.end` TaskEvent，文件被删除，计数据此更新

### US-D2 损坏文件跳过（失败向）
- **Given** spool 目录同时有 1 个损坏文件与 1 个合法 `UserPromptSubmit` 文件
- **When** `drain()`
- **Then** 合法文件产出 `.start` 事件；损坏文件被记录并删除、不影响合法文件；两文件均不残留

### US-D3 乱序事件守卫（边界）
- **Given** 会话 s1 已收到 `start@t2`
- **When** 迟到的 `pause@t1`（t1<t2）到达
- **Then** 陈旧事件被忽略，s1 仍为工作中

### US-D4 重复结束幂等（边界）
- **Given** 会话 s1 已 `end`（completed=1，idle）
- **When** 再收到一个更晚的 `end`
- **Then** completed 保持 1（不重复计）

---

## Epic E：桌面宠物窗口

### US-E1 显示与拖动（正向）
- **Given** 宠物窗开启
- **When** 我拖动小猫
- **Then** 窗口跟随移动，且不抢占其它应用焦点（点击不激活）

### US-E2 状态驱动表现（正向）
- **Given** 有工作中任务
- **When** 我看宠物
- **Then** 小猫呈现 working 表现；当仅有等待中任务时呈现 waiting；无任务时呈现 idle

### US-E3 互动反馈（正向）
- **Given** 宠物窗开启
- **When** 我点击「撸猫」
- **Then** 小猫给出即时互动反应（不改变能量数值）
