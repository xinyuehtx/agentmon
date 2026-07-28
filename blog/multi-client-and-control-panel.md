# 一只小猫，七个宿主：把监控扩到多客户端 + 做一个独立控制台

> 需求 slug：`multi-client-and-control-panel` ｜ 关联：[RFC](../rfcs/multi-client-and-control-panel.md) · [SPEC](../specs/agent-task-monitor.md#55-多客户端集成注册表--可插拔安装器新增) ｜ 发布：**v0.5.0**

这是 agentmon 的第二个大需求落地记录，迭代自 [`agent-task-monitor`](./agent-task-monitor.md)。目标两件事：**采集从 2 个客户端扩到 5 个集成**（Claude Code / Qoder / qoderwork·QwenWork / Codex / opencode），以及把塞满菜单栏的一堆开关**搬进一个独立控制台窗口**（仪表盘 / 监控设置 / 桌宠设置）。本文沉淀关键决策与踩坑。

## 1. 需求背景

老菜单把「集成开关 / 各客户端计数 / 宠物生命周期 / 诊断 / 日志」全堆在下拉里，拥挤且不可扩展；采集也只有 Claude Code + Qoder。用户要求：菜单栏**只显示总运行状态数**，细节进独立面板；采集**原生**扩到更多客户端。

流程上，用户明确要求**先出 RFC 评审**再决定是否提交——于是本次严格走了 `方案 → RFC（卡点评审）→ 实现 → 回归 → 发布` 的顺序，RFC 里的两个未决点由用户拍板后才动手。

## 2. 三种接入机制：一个协议收口

不同客户端的 hook 机制差异很大，抽象成统一契约 `IntegrationInstaller { install()/uninstall()/isInstalled() }`，用**数据驱动注册表** `IntegrationRegistry` 描述 + 工厂构造：

| 机制 | 客户端 | 落地 |
| --- | --- | --- |
| `.claudeHooks` | Claude Code / Qoder / qoderwork·QwenWork | 复用既有 `ClaudeHookInstaller`，只换 settings.json 路径 + 客户端标签 |
| `.codexHooks` | Codex | 新增 `CodexHookInstaller`：`~/.codex/config.toml` 末尾追加**标记块** `[[hooks.*]]`（不引 TOML 解析依赖） |
| `.opencodePlugin` | opencode | 新增 `OpencodePluginInstaller`：写 `~/.config/opencode/plugins/agentmon.js` 插件文件 |

关键发现：**Codex 的 command hook 也从 stdin 收 `hook_event_name`+`session_id`，与 Claude 同构**——所以 `agentmon-hook` 的 stdin 解析路径原样复用，Codex 只是配置文件格式（TOML）不同而已。

## 3. 逆向 QwenWorkCN.app：别猜，去读

RFC 阶段最大的不确定性是 `qoderwork` / `qwenwork` 到底怎么接。用户一句「qwenwork 可以逆向 `/Applications/QwenWorkCN.app`」直接把猜测变成了实证。`app.asar` 字符串取证结论：

- 它是 **Electron 壳**（`cn.qwenwork.desktop.mac`），打包了 `bin/qoderclicn`（约 100 MB）——**内核就是 Qoder CLI 的 CN 变体**。
- 命中 `hook_event_name`、`UserPromptSubmit`/`Notification`/`Stop`/`PreToolUse`…——**Claude 兼容 hooks**。
- 配置目录默认 `~/.qoderwork/`（`settings.json` 实证确认），且 **env 可覆盖**（`QODER_CONFIG_DIR`，12 处引用）。
- `.qwenwork.cn` 只是**遥测埋点 + 云端点**，不是本地配置；没有 `~/.qwenwork/settings.json`。

**由此得出关键设计**：qwenwork 与 qoderwork 在 hook 层同源、默认共用 `~/.qoderwork/settings.json`。若当两个集成、都往同一文件注入各自 reporter，会**重复 hook → 双重计数**。评审拍板：**合并为一个开关**，UI 标注「对 qoderwork 与 QwenWork 两个应用都生效」；另一个未证实的 `qoderwake` **本期跳过**。

> 教训：接第三方客户端前，先把它的 `.app` / CLI 扒一遍配置目录与 hook 名，比对着文档猜靠谱得多。

## 4. 上报器参数契约：为 opencode 避开 stdin 阻塞

opencode 无 settings hooks，只能写 JS 插件订阅 `event` 钩子，再 shell 调上报器。问题：插件在 TUI 会话里跑，若上报器无脑 `readDataToEndOfFile()`，stdin 是 TTY 会**阻塞**。

解法是把上报器调用抽成可测的 `HookInvocation.resolve`，扩展参数契约：

```
agentmon-hook <client> [<kind> [<sid>]]
  0/1 个额外参数 → 读 stdin（Claude 家族 / Codex，均 Claude 同构）
  2~3 个额外参数 → 用归一化 kind（start/pause/end），不读 stdin（opencode 插件用）
```

`main.swift` 先用 `needsStdin(arguments:)` 判断，归一化模式**根本不碰 stdin**——既避开阻塞，也免了在 Bun `$` 里做脆弱的 JSON 转义。`ClaudeEventMapper` 相应加了 `PermissionRequest→pause`（Codex）与归一化 `start/pause/end`（opencode）。

## 5. 关键设计决策

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| Codex 配置编辑 | 标记块文本追加，不引 TOML 库 | 保持纯 Swift + swift-format；标记块可精确回滚，不重写用户配置 |
| Codex 事件源 | hooks framework（stdin） | `notify` 是单标量、会覆盖用户值、无 session_id/无 start |
| `[features] hooks=true` | **不写进标记块** | 用户若已有 `[features]` 表，重复表头是 TOML 错误——改由面板提示 `/hooks` 信任 |
| qwenwork vs qoderwork | 按同源合并为一个开关 | 逆向证明共用 `~/.qoderwork`，独立会双重计数 |
| 「是否启用」 | 读 `isInstalled()` 派生，不持久化 | 避免与用户手改配置漂移；只持久化自定义路径 + 桌宠偏好 |
| 控制台窗口 | 打开期临时切 `.regular` | LSUIElement 应用 `.accessory` 下文本框拿不到稳定键盘焦点，关闭再复位 |
| 仪表盘数据 | 只用现有三态元数据 | 守住只读、最小采集、无 token/内容/网络的隐私边界 |
| 能量参数改动 | 持久化 + 下次启动生效 | 运行时重建引擎会打乱 energy/level 状态，不值当 |

## 6. 踩坑记录

- **别猜 Codex 的 TOML schema**：动手前用文档核实是 `[[hooks.<Event>]]` + 嵌套 `[[hooks.<Event>.hooks]]`（`type`/`command`），不是 `[[hooks]]` 带 event 字段，也不是扁平 `[hooks]`。猜错就是装了个不生效的块。
- **TOML 追加要留一空行**：EOF 追加 `[[hooks.X]]` 合法，但若用户文件结尾是多行值，紧贴着追加可能落进上一段值里——install 前先把尾部规范成「内容 + 空行」。
- **`NavigationSplitView` 的 List selection 要 `Optional`**：`@State var section: Section`（非可选）绑不上，得 `Section?` 再在 detail 里 `?? .dashboard`。
- **`try? optionalChain?.throwingCall()` 会套成 `Bool??`**：`(try? installers[id]?.isInstalled()) ?? false` 类型绕；老老实实 `if let inst = ... { installed = (try? inst.isInstalled()) ?? false }` 更清楚也更对。
- **opencode 插件是 fire-and-forget**：`opencode run` 可能在异步 handler 冲完前退出（交互式 TUI 不受影响）；插件 API 尚未 1.0，`plugins/` vs `plugin/` 目录跨版本会变——路径做成可编辑 + env 可覆盖 + 文件带首行标记兜底。
- **`swift-format --strict` 只认 120 列**：一行 `XCTAssertTrue(... is ClaudeHookInstaller)` 超长；`format -i` 自动折行后再 `lint --strict` 归零，别手抖对齐。
- **改了 `Diagnostics` 签名要顺带修调用方与测试**：`Doctor.swift` 和 `DiagnosticsTests` 都在编译期炸出来——泛化成遍历 `[(descriptor, installer)]` 后，报告顺带覆盖全部 5 个客户端。

## 7. 验证结果

- `swift test`：**106 用例全通过**（79 → +27：注册表 / Codex·opencode 安装器 / HookInvocation / AppSettings / sessionRows / recentActivity / 事件映射）。
- `swift-format lint --strict`：**0 warning**。
- 无头烟测：`echo '{"hook_event_name":"Stop","session_id":"s1"}' | agentmon-hook Codex` 与 `agentmon-hook opencode start s1` 均正确原子写出 spool；`--doctor` 列出全部 5 个客户端并遵循 env 路径覆盖；`--selftest` OK。
- **CI（GitHub Actions）**：`check` / `uitest` / `package` 三 job 全绿，`v0.5.0` 附 `agentmon.zip` 自动发布。

## 8. 可复用经验

1. **接第三方客户端先逆向**：`.app` 的 `app.asar` / bundle 里 `grep` 一遍配置目录、hook 名、env 覆盖键，比啃文档猜快且准。
2. **同源客户端按"解析后路径"去重**：一份 settings.json 只该有一个 reporter，否则重复计数。
3. **归一化事件名收口在一个 mapper**：不同客户端、不同机制（stdin / 参数）最终都汇到 `start/pause/end`，下游零分支。
4. **动 stdin 的 CLI 要先判断需不需要读**：TTY 下无脑读会挂；用参数形态显式区分。
5. **动用户配置的老三样照旧**：先备份、可幂等、可精确回滚、损坏即中止——TOML/JS 文件和 JSON 一视同仁。
6. **RFC 卡点是特性**不是负担：把「qwenwork 合并 / qoderwake 跳过」这类不可逆决策摆到评审台面上定了再写码，省掉返工。
