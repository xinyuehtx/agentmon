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
- **控制台**：仪表盘（各客户端计数 / 会话看板 / 活动流 / 能量等级）· 监控设置（逐客户端开关、可编辑路径、诊断/日志、能量参数）· 桌宠设置（显示隐藏、成长形态进度）。
- **桌面宠物**：**草系罗盘猫（verdant）**随状态播放逐帧动画（发呆/干活/等待/完成/进化/饿了/跳跃/技能，透明精灵）；**右键 →「隐藏宠物」**，之后从控制台「桌宠设置」重开；可拖动。**Lv0–Lv3 四档，等级即形态：Lv0 蛋 → Lv1 幼体 → Lv2 少年 → Lv3 成熟，升级即进化**；每升一级解锁更多随机空闲动作（跳跃/技能/撒花，越高级越活泼）。
  - 接新素材：把每个形态每个动作的原创视频放进 `mons/<角色>/<形态>/<动作>.mp4`，跑 `python3 scripts/video_to_pack.py --mon-dir mons/<角色> --out assets/pets_raster/packs/<角色>`（抽帧/抠底/对齐/拼条 + 生成 v3 manifest）。详见 [`.claude/skills/pet-material-pipeline`](./.claude/skills/pet-material-pipeline/SKILL.md)。
  - **本地自定义桌宠**（不随发布分发）：把任意图集包放到 `~/Library/Application Support/agentmon/custom_pet/`，App 会优先加载；删除该目录即恢复随包原创。⚠️ 若使用第三方素材，请自行遵循其授权，切勿提交/分发。
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
python3 scripts/video_to_pack.py --mon-dir mons/<角色> --out assets/pets_raster/packs/<角色>   # 视频 → 图集

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
assets/pets_raster/packs/  宠物图集包（每包含 v3 manifest.json + 各形态动作条；由 scripts/video_to_pack.py 生成）
scripts/         package.sh（打 .app）· make-icon.swift（图标）· video_to_pack.py（视频→图集）· classify_videos.py · preview-packs.py
tests/unit/      单元测试     tests/integration/  集成测试     tests/e2e/  XCUITest 场景
```

## 能量玩法

| 事件 | 能量变化（默认，可配置） |
| --- | --- |
| 工作中任务 | `+2 / 分钟` |
| 等待中任务 | `−1 / 分钟` |
| 完成任务 | `+30`（一次性） |
| 无任务 | `−0.5 / 分钟` |

能量累计跨过门槛触发升级（默认 3 档 `[100,250,500]`，约 3 天活跃即可从 **Lv0**（蛋）升到满级 **Lv3**（成熟）；**等级即形态，升级即进化**，并解锁更多随机空闲动作（跳跃/技能/撒花）。等级单生命内单调不回退。数值见 `config.json`（`~/Library/Application Support/agentmon/`）。

## 版权与素材合法性

- **本仓库与发布包仅含原创素材**（草系罗盘猫 verdant：4 形态 × 8 动作，由作者原创视频经 `scripts/video_to_pack.py` 生成），可自由分发。
- **第三方素材（DyberPet / BongoCat / 各类同人模型等）不入库、不随发布分发**：其多为 GPL-3.0（传染性 copyleft）或受版权保护的 IP，自行添加「仅自用」声明并不能为他人 IP 重新授权，也不能使公开分发合法。
- **本地使用（合规）**：把**自行下载/制作**的图集包放到 `~/Library/Application Support/agentmon/custom_pet/`，App 会优先加载，供**个人本地使用**；删除该目录即恢复随包原创。此路径下素材**只在你本机**，不进入本仓库/发布包。

