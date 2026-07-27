# RFC: agentmon 多客户端采集 + 独立控制台面板

- **Slug**: `multi-client-and-control-panel`
- **状态**: Accepted（已评审通过 2026-07-27）
- **作者**: agentmon team
- **日期**: 2026-07-27
- **关联**: 迭代自 [`agent-task-monitor`](./agent-task-monitor.md)
- **评审决议**：① qoderwork 与 qwenwork **合并为一个开关**，UI 明确标注「对 qoderwork 与 QwenWork 两个应用都生效」；② **qoderwake 跳过**，本期不做。

---

## 1. 背景

当前 agentmon 把「集成开关 / 各客户端计数 / 宠物生命周期 / 诊断 / 日志」全部堆在菜单栏下拉菜单里（见现状截图），信息拥挤且不可扩展；采集端只做了 **Claude Code + Qoder** 两个客户端。

用户诉求：

1. **扩展采集**到更多客户端：`qoder`、`opencode`、`qoderwork`、`qoderwake`、`codex`、`qwenwork`（Claude Code 已有，保留）——**全部原生真实采集**。
2. **菜单栏只保留总运行状态任务数**（`▶工作 ⏸等待 ✓完成`），其余细节移出菜单。
3. 新增**独立桌面控制台面板**：更详细的仪表盘（交互参考 [Claude-Code-Agent-Monitor](https://github.com/xinyuehtx/Claude-Code-Agent-Monitor)，暗色卡片/看板/活动流）、监控设置开关、桌宠设置面板。

## 2. 目标 / 非目标

### 2.1 目标
1. 数据驱动的**集成注册表** + 统一 `IntegrationInstaller` 契约，支持 3 种接入机制，覆盖 7 个客户端。
2. 菜单栏精简为「总数标题 + 打开控制台 + 退出」。
3. 独立控制台窗口：**仪表盘 / 监控设置 / 桌宠设置** 三段，实时刷新，可开关集成、可编辑配置路径、可调能量参数、可管理宠物。
4. 仪表盘**沿用现有三态事件数据**（按客户端 + 会话），不引入新的隐私采集。
5. 每个安装器**幂等、写前备份、可精确回滚**，且路径 env 可覆盖、UI 可编辑，测试用临时目录不碰真实用户配置。

### 2.2 非目标
- 不采集 token / 费用 / 模型 / 对话内容（保持只读、最小元数据、无网络）。
- 不复刻参考面板的 Kanban 服务端分页、Sankey、Run-Claude 子进程、Config Explorer 等重型能力。
- 不做云同步 / 跨平台 / 多用户。
- 不干预（暂停/杀死）任何 Agent。

## 3. 逆向取证：qwenwork / qoder 家族的真实接入方式（关键前置）

用户提示可逆向 `/Applications/QwenWorkCN.app`。实测结论（`app.asar` 字符串取证）：

| 取证项 | 结论 |
| --- | --- |
| 形态 | Electron 桌面应用，bundle id `cn.qwenwork.desktop.mac` |
| 内核 | 打包了 `Contents/Resources/bin/qoderclicn`（约 100 MB，Qoder CLI CN 变体）——**QwenWork 本质是 Qoder CLI 的品牌壳** |
| Hook 机制 | **Claude 兼容**：出现 `hook_event_name`，事件含 `UserPromptSubmit` / `Notification` / `Stop` / `PreToolUse` / `PostToolUse` / `SessionStart` |
| 配置目录 | 默认 `~/.qoderwork/`（含 `settings.json`、`gcp-oauth.json`、`skills/`、`.trash`）；目录名模板化（`.qoderworkDirName`），**env 可覆盖**：`QODER_CONFIG_DIR`（12 处引用）、`QODERCN_CONFIG_DIR` |
| `.qwenwork.cn` 等字符串 | 是**遥测埋点事件名 + 云端点**（如 `.qwenwork.cn/qwenwork/computer-use/...`），**不是**本地配置路径 |
| `~/.qwenwork/settings.json` | **未发现** |

**设计含义（评审已定）**：
- `qoderwork` 的路径 `~/.qoderwork/settings.json` 由此**实证确认**（非猜测），且 hooks 为 Claude 兼容。
- `qwenwork` 与 `qoderwork` 在 hook 层**同源、默认共用同一个 `~/.qoderwork/settings.json`**。若把两者当成两个独立集成、都往同一个 settings.json 注入各自 reporter 命令，会产生**重复 hook → 双重计数**。
- **决议①**：**合并为单一集成开关**（id `qoderwork`，displayName「qoderwork / QwenWork」），UI 明确标注「对 qoderwork 与 QwenWork 两个应用都生效」。路径仍可编辑 / 可用 `QODER_CONFIG_DIR` 区分。
- **决议②**：`qoderwake` **本期跳过**（QwenWork 中无任何证据，暂不做）。

## 4. 详细方案

### 4.1 集成架构：注册表 + 可插拔安装器（Core）

- `IntegrationInstaller` 协议：`install() / uninstall() / isInstalled() throws`。现有 `ClaudeHookInstaller` 已天然符合（加空 `extension` 即可）。
- `IntegrationMechanism { claudeHooks, codexHooks, opencodePlugin }`。
- `ClientIntegration` 描述符：`id, displayName, clientLabel, symbol, mechanism, defaultPath, events, verified, supportsWaiting, requiresTrustStep`。
- `IntegrationRegistry`：`descriptors(customPaths:) -> [ClientIntegration]` + 工厂 `installer(for:reporterCommand:)`。**按解析路径去重**。

客户端描述符表（评审后：qoderwork/qwenwork 合并，qoderwake 移除）：

| id | 名称 | clientLabel | 机制 | 默认路径 | events | 备注 |
|---|---|---|---|---|---|---|
| claude | Claude Code | Claude Code | claudeHooks | `~/.claude/settings.json` | UserPromptSubmit, Notification, Stop | 现状保留 |
| qoder | Qoder | Qoder | claudeHooks | `~/.qoder/settings.json` | +SubagentStart | 现状保留 |
| qoderwork | qoderwork / QwenWork | qoderwork | claudeHooks | `~/.qoderwork/settings.json` | UserPromptSubmit, Notification, Stop | ✅ 逆向确认；**一个开关对 qoderwork 与 QwenWork 都生效**；env `QODER_CONFIG_DIR` |
| codex | Codex | Codex | codexHooks | `~/.codex/config.toml` | UserPromptSubmit, PermissionRequest, Stop | TOML；启用后需 `/hooks` 信任一次 |
| opencode | opencode | opencode | opencodePlugin | `~/.config/opencode/plugins/agentmon.js` | 插件驱动 | 无 settings hooks |

> 共 **5 个集成开关**（Claude Code / Qoder / qoderwork·QwenWork / Codex / opencode）。qoderwake 本期不做。

### 4.2 Codex 安装器（TOML 标记块，不引依赖）

- Codex hooks framework 的 command hook 同样从 **stdin 收 `hook_event_name`+`session_id`**（与 Claude 同构）→ `agentmon-hook` 的 stdin 路径**原样复用**，仅配置文件格式不同。
- `CodexHookInstaller`：在 `~/.codex/config.toml` **末尾追加**被 `# >>> agentmon >>>` / `# <<< agentmon <<<` 包裹的 `[[hooks.UserPromptSubmit/PermissionRequest/Stop]]` 块（`command` 内嵌 `.../agentmon-hook Codex`）。install 先备份 `.agentmon.bak` + 补空行 + 原子写；uninstall 精确删标记区间；isInstalled 查标记 + reporter。**不引 TOML 解析库**（保持纯 Swift + swift-format），**不动 `notify`**（会覆盖用户标量值）。
- 事件映射：`PermissionRequest → .pause`。

### 4.3 opencode 安装器（JS 插件 + hook argv 契约）

- `OpencodePluginInstaller`：写入 `~/.config/opencode/plugins/agentmon.js`（首行标记 `// agentmon-plugin v1`，内嵌 reporter 绝对路径）；已存在他人文件先备份；uninstall 校验标记后删除。
- 插件订阅 `event`：`message.part.updated`→start（去抖）、`permission.asked`→pause、`permission.replied`→start、`session.idle`/`session.error`→end，调 `agentmon-hook opencode <kind> <sid>`。
- **hook 参数契约扩展**（抽到可测的 Core `HookInvocation.resolve(arguments:stdin:)`）：`agentmon-hook <client> [<kind> [<sid>]]`——0/1 个额外参数走 stdin（Claude 家族 + Codex）；2–3 个走「已归一化 kind」直写（opencode 用，避免 JS 里脆弱的 JSON 转义）。`Sources/Hook/main.swift` 变薄为一行调用。
- `ClaudeEventMapper` 追加归一化名：`.start=[…,"start"]`、`.pause=[…,"PermissionRequest","pause"]`、`.end=[…,"end"]`（全部叠加，旧客户端不产生这些名字，无回归）。

### 4.4 仪表盘只读数据（Core）

- `TaskStore.sessionRows() -> [SessionRow{client, sessionID, state, lastActivity}]`（看板）。
- `MonitorCoordinator.recentActivity(limit:) -> [ActivityItem{client, sessionID, kind, at}]`（活动流，有界环形缓冲）。`MonitorSnapshot` 结构不动（保护其 Equatable 测试）。

### 4.5 持久化（Core）

- 新增 `AppSettings{schemaVersion, customPaths:[id:path], petVisible, petScale?, petOrigin?}` + `AppSettingsStore`（原子写、`decodeIfPresent` 向后兼容，仿 `EnergyConfig`/`StateStore`），落 `~/Library/Application Support/agentmon/app-settings.json`。
- **「是否启用」不持久化**——以 `installer.isInstalled()`（读各客户端自身配置）为准，避免与手改漂移；仅持久化自定义路径与桌宠 UI 偏好。`EnergyConfig` 仍走 `config.json`。
- `AgentmonPaths` 按现有模式新增 env 可覆盖路径：`qoderworkSettings`/`qoderwakeSettings`/`qwenworkSettings`/`codexConfig`/`opencodePlugin`/`appSettingsFile`。

### 4.6 控制台窗口 + 实时模型（App）

- `AppModel: ObservableObject`（仿 `PetState`）：发布仪表盘字段、宠物状态、集成行 `[IntegrationRow]`、`energyConfig`；暴露动作闭包（`onToggleIntegration/onSetPath/onSaveConfig/onTogglePet/onHatch/onShowActive/onShowSkin/onRunDiagnostics/onOpenLog`）由 `AppDelegate` 接线，SwiftUI 与 AppKit 解耦。
- `ControlPanelWindowController`：单例复用 `NSWindow`，内容 `NSHostingController(ControlPanelView().environmentObject(appModel))`。LSUIElement 应用打开时临时切 `.regular`（拿键盘焦点）+ `activate` + `makeKeyAndOrderFront`；`windowWillClose` 复位 `.accessory`；已开则前置。
- `ControlPanelView`：`NavigationSplitView` 暗色主题三段：
  - **仪表盘**：StatCard 行（工作/等待/完成/活跃客户端）+ 各客户端计数 + 三列看板（工作中/等待中/已完成）+ 活动流 + 能量/等级/宠物状态卡；每次 pump 刷新。
  - **监控设置**：`ForEach(integrations)` 开关 + 可编辑路径 + 状态/错误；qoderwake「未验证」徽标、qwenwork「与 qoderwork 同源」提示、Codex「需 `/hooks` 信任一次」提示；运行诊断 / 打开日志按钮；`EnergyConfig` 编辑。
  - **桌宠设置**：显示/隐藏、孵化新宠物（保留未毕业确认）、收藏皮肤衣柜（物种→形态切换 / 显示当前）、缩放/位置重置。

### 4.7 菜单精简（App）

- 状态标题保留 `▶ ⏸ ✓` 总数；下拉菜单仅剩「打开控制台…」+ 分隔 + 「退出 agentmon ⌘Q」，左键点击状态项直接开面板。
- 原 `toggleIntegration/hatchNew/showActive/selectSkin/runDiagnostics/openLog` 逻辑**不删**，经 `AppModel` 闭包在面板复用。`Diagnostics.report(...)` 泛化为遍历 `[(ClientIntegration, IntegrationInstaller)]`。

### 4.8 改动文件清单

- 新增 Core：`IntegrationInstaller` / `IntegrationRegistry` / `CodexHookInstaller` / `OpencodePluginInstaller` / `HookInvocation` / `AppSettings`.swift
- 新增 App：`AppModel` / `ControlPanelWindowController` / `ControlPanelView`（+ 子视图）.swift
- 改：Core `ClaudeEventMapper` / `AgentmonPaths` / `Diagnostics` / `TaskStore` / `MonitorCoordinator`；`Sources/Hook/main.swift`；App `AppDelegate`
- 复用模板：`ClaudeHookInstaller`（安装器写法）、`StateStore`（原子写/兼容解码）、`PetState`（ObservableObject）、`PetPanel`（窗口）

## 5. 备选方案对比

| 决策点 | 选定 | 备选 | 取舍 |
|---|---|---|---|
| Codex 配置编辑 | 标记块文本追加 | 引 TOMLKit(C++)/TOMLDecoder | 保持纯 Swift + swift-format；标记块可精确回滚，避免重写用户配置 |
| Codex 事件源 | hooks framework（stdin，与 Claude 同构） | `notify` 命令 | notify 为单标量、会覆盖用户值、无 session_id/无 start |
| opencode 接入 | 写 JS 插件文件 | SSE 事件流常驻订阅 | 插件零常驻进程、随客户端生命周期，契合 hook 模型 |
| qwenwork vs qoderwork | 按解析路径去重（默认同源） | 强行当两个独立集成 | 逆向证明同用 `~/.qoderwork`，独立会双重计数 |
| 「是否启用」状态 | 读 `isInstalled()` 派生 | 持久化 enabled 集合 | 避免与用户手改配置漂移 |
| 面板窗口 | 打开期临时 `.regular` | 常驻 `.accessory` + activate | `.accessory` 下文本框拿不到稳定键盘焦点 |
| 仪表盘数据 | 现有三态元数据 | 扩展采集 token/工具调用 | 守住只读最小采集与隐私边界（非目标） |

## 6. 迁移与回滚

- **向后兼容**：`app-settings.json` 全字段 `decodeIfPresent`；旧 `state.json`/`config.json` 不变。菜单精简不影响已注入的 hooks。
- **各集成回滚**：每个安装器 install 前写 `*.agentmon.bak`，uninstall 精确移除 agentmon 注入项，保留用户其它配置；面板一键停用即回滚。
- **特性回滚**：新增文件为主、老逻辑经闭包保留；如需撤销，恢复旧 `AppDelegate.menuNeedsUpdate` 即可（老菜单逻辑仍在版本历史）。
- **失败安全**：JSON/TOML 损坏时安装器抛错不写（沿用现有守卫）。

## 7. 灰度策略

- 默认仅 Claude Code/Qoder 与老行为一致（不主动开启新客户端）。
- 新客户端默认**未启用**，用户在「监控设置」逐个开；qoderwake/qwenwork 带明确「未验证 / 同源」提示，降低误配风险。
- 沙箱验证：`AGENTMON_HOME` / `AGENTMON_CODEX_CONFIG` / `AGENTMON_OPENCODE_PLUGIN` 等 env 指向临时文件，先自测再对真实配置操作。

## 8. 验收标准

1. `swift build`（三产物）、`swift test`（新+旧全绿）、`swift-format lint --strict --recursive Sources tests UITests` 通过。
2. 注册表：7 个描述符、默认路径正确、自定义路径覆盖生效、同路径去重、工厂按机制返回正确类型。
3. Codex 安装器：临时 TOML 上 install 追加块 + 备份；幂等（标记在则不重复）；uninstall 精确删块、其余字节不变；`isInstalled` 检出。
4. opencode 安装器：写带标记文件 + 内嵌 reporter；已存在他人文件先备份；uninstall 删本插件；`isInstalled` 首行标记。
5. `HookInvocation.resolve`：0/1/2/3 参数与 stdin JSON 解析、缺省 session 兜底。
6. 事件映射：`PermissionRequest→pause`、归一化 `start/pause/end` 生效，旧映射无回归。
7. 手动：面板逐个开关 → 对应 settings.json/TOML 块/插件文件出现并能干净回滚；`echo '{"hook_event_name":"Stop","session_id":"s1"}' | agentmon-hook Codex` 与 `agentmon-hook opencode start s1` 后 spool 落文件、仪表盘一个 pump 周期内更新。
8. 菜单仅剩「总数标题 / 打开控制台 / 退出」；控制台三段可用、实时刷新。

## 9. 风险 / 未决

- **qwenwork/qoderwork 同源（评审已定①）**：合并为单一开关，默认 `~/.qoderwork/settings.json`，UI 标注「对 qoderwork 与 QwenWork 都生效」；如需分别计数，用户可为某一应用设独立 `QODER_CONFIG_DIR` 或改面板路径（本期不提供拆分 UI）。
- **qoderwake（评审已定②）**：本期跳过，不做。
- **Codex hooks 门控**：command hook 需在 Codex 内 `/hooks` 信任一次；仅改用户级 `~/.codex/config.toml`（受支持路径）。
- **opencode 插件 API 未 1.0**：事件名/`properties`、`plugins/` vs `plugin/` 目录跨版本或变——路径可编辑/env 可覆盖、文件带标记兜底。
- **LSUIElement 焦点**：打开期切 `.regular`、关闭复位 `.accessory`；确保 ⌘W 也复位、重开只前置单实例。

## 10. 附录：逆向命令留痕

```
# bundle
Contents/Info.plist → CFBundleIdentifier=cn.qwenwork.desktop.mac
Contents/Resources/bin/qoderclicn (≈100MB, Qoder CLI 内核)
# app.asar 字符串取证
grep -a hook_event_name            → 命中（Claude 兼容 hooks）
grep -a .qoderwork/settings.json   → 命中（默认配置路径）
grep -a QODER_CONFIG_DIR           → 12 处（配置目录 env 覆盖）
grep -a .qwenwork.cn               → 遥测/云端点，非本地配置
```
