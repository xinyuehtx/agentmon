# agentmon 🐱

> Agent 小精灵 —— 一个 macOS 上的 Agent 长任务监控工具，用一只 AI 原创小猫陪你一起「养成」。

agentmon 监控本地已安装的 Agent 客户端（Claude Code、Qoder、qoderwork/QwenWork、Codex、opencode）长任务的**启动 / 暂停 / 结束**状态，并以三种形态呈现：

- **菜单栏（menubar）**：只显示全部客户端的总运行状态 `▶工作中 ⏸等待中 ✓已完成`。
- **控制台（独立窗口）**：详细仪表盘（各客户端计数 / 会话看板 / 活动流 / 能量等级）+ 监控设置（逐客户端开关、可编辑路径、能量参数）+ 桌宠设置。
- **桌面小工具（宠物）**：一只小猫随你的工作状态积累或消耗能量，能量达到门槛即可**进化（换肤）**。

## 开发工作流

本仓库遵循 [`AGENTS.md`](./AGENTS.md) 定义的 10 步协作工作流（方案 → RFC → SPEC/Story/测试 → 审查 → 实现 → 验证 → 沉淀）。

- 技术栈：原生 Swift（SwiftPM 包；macOS 13+ 菜单栏 App + 桌面宠物浮窗）
- 需求文档：[`rfcs/`](./rfcs) · [`specs/`](./specs) · [`stories/`](./stories) · [`blog/`](./blog)

在菜单栏点击「打开控制台…」→「监控设置」，为每个客户端打开开关即可把上报 hooks 接入对应客户端
（写前自动备份，可一键停用回滚）：

- **Claude Code / Qoder / qoderwork·QwenWork**：合并写入各自 `settings.json` 的 hooks（`~/.claude`、`~/.qoder`、`~/.qoderwork`）。
  - qoderwork 与 QwenWork 同源（QwenWorkCN.app 内核为 `qoderclicn`），**一个开关对两个应用都生效**；如需分开可用 `QODER_CONFIG_DIR` 或改路径。
- **Codex**：在 `~/.codex/config.toml` 追加标记块 hooks；**启用后需在 Codex 里执行一次 `/hooks` 信任**。
- **opencode**：写入 `~/.config/opencode/plugins/agentmon.js` 插件。

> ⚠️ **启用集成后，需在对应客户端中新开一个会话**，hooks 才会加载生效——之后跑任务即可在控制台看到计数变化。

## 使用与交互

- **菜单栏**：猫图标 + `▶工作中 ⏸等待中 ✓已完成`（总数）；点开选「打开控制台…」进入详细面板。
- **控制台**：仪表盘（各客户端计数 / 会话看板 / 活动流 / 能量等级）· 监控设置（逐客户端开关、可编辑路径、诊断/日志、能量参数）· 桌宠设置（显示隐藏、孵化、收藏皮肤）。
- **桌面宠物**：随状态播放**原创手绘图集动画**（idle/工作/等待/完成，逐帧透明精灵，交叉溶解补帧、30fps+ 平滑播放）；**右键 →「隐藏宠物」**，之后从菜单栏「显示宠物」重开；可拖动。三只原创精灵（草/火/水）× 四阶段（蛋/幼年/成熟/完全），每次安装随机分到一只（卸载重装重掷）。图鉴 [`docs/pet-sprites.png`](./docs/pet-sprites.png)，动画预览 [`docs/pet-preview.html`](./docs/pet-preview.html)。
  - 接新素材：按 [`docs/pet-art-prompt.md`](./docs/pet-art-prompt.md) 为每个动作生成一组**独立帧序列**（`<species>_<stage>_<action>_NN.png`，洋红底单只主体）→ `swift scripts/process-packs.swift <源目录>`（分组/抠底/公共对齐/拼条）→ `assets/pets_raster/`。流水线**增量**运行：只更新处理成功的动作，多主体拼图/异常过宽的帧会被跳过并保留旧素材。
- **能量/进化**：见下方「能量玩法」。

## 故障排查 / 诊断

看不到监控信息时，按顺序自查：

1. **命令行诊断**：`agentmon --doctor`（或控制台「监控设置 → 运行诊断…」）打印一份报告——逐客户端检查集成是否启用、上报器是否存在可执行、spool 是否可写、运行状态、最近日志、并给出建议。
2. **看日志**：菜单「打开日志文件」或 `~/Library/Application Support/agentmon/agentmon.log`（只记事件元数据，不含任务内容）。
3. **最常见原因**：启用集成后**没有新开 Claude Code 会话** → hooks 未加载 → 无事件。新开会话后再跑任务。

## 构建与运行

```bash
swift build                 # 编译 Core + App + agentmon-hook
swift test                  # 单元 + 集成测试
swift-format lint --recursive Sources tests   # 静态检查（经 xcrun）
swift scripts/make-icon.swift                 # 重新生成 App 图标
swift scripts/process-packs.swift <源目录>    # 处理宠物图集 → assets/pets_raster + docs/

.build/debug/agentmon --selftest   # 无 GUI 自检：验证摄取→计数→能量链路
.build/debug/agentmon --doctor     # 无 GUI 打印诊断报告
.build/debug/agentmon              # 启动菜单栏 App + 桌面宠物（需图形会话）
```

## 项目结构

```
Sources/Core/    纯逻辑（可测，无 UI 依赖）：TaskStore / EnergyEngine / SpoolIngestor /
                 ClaudeHookInstaller / CodexHookInstaller / OpencodePluginInstaller /
                 IntegrationRegistry / HookInvocation / StateStore / AppSettings /
                 MonitorCoordinator / Diagnostics / AgentmonLog / PetSelection / RasterLibrary
Sources/App/     菜单栏 App + 控制台窗口（AppModel / ControlPanelView）+ 光栅宠物浮窗
                 （AppKit + SwiftUI）+ --selftest / --doctor
Sources/Hook/    agentmon-hook：多客户端 hook 上报器（stdin 或 <client> <kind> <sid> 参数 → 原子写 spool）
assets/pets_raster/  宠物图集帧 + manifest.json（由 scripts/process-packs.swift 生成）
scripts/         package.sh（打 .app）· make-icon.swift（图标）· process-packs.swift（图集）
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
