# AGENTS.md — AI Agent 协作工作流

本文档定义 AI Agent（Claude / 其他）在本仓库承接需求时必须遵守的工作流。目的是让需求 → 方案 → 设计 → 实现 → 验证全过程可追溯、可审查、可回滚。

## 项目概述

agentmon（Agent 小精灵）是一个 Agent 任务监控工具，理念类似宝可梦（pokémon）：

- **核心能力**：监控 Agent 长任务是否执行完成，并通过一只「宠物」实时反映任务状态。
- **技术栈**：原生 Swift（SwiftPM 包；macOS 菜单栏 App + 桌面宠物浮窗）。
- **构建命令**：`swift build`（编译）、`swift test`（测试）、`swift-format lint --recursive Sources tests`（静态检查）。GUI/E2E 可走 `xcodebuild test`（XCUITest）。

## 工作流（10 步）

承接每个非平凡需求时按顺序执行。每个"等待用户同意"的节点都是**强卡点**，未获明确同意不得跳到下一步。

### 1. 方案推荐
- 输出**简要**方案推荐，控制在屏幕一页内。
- 至少给出 **1 个备选方案**，并标明推荐项与理由。
- 包含：核心思路、改动点、收益预估、风险、工作量量级。
- **卡点**：等待用户同意推荐方案后再继续。

### 2. 编写 RFC
- 将通过的方案细化为 RFC，写入 `rfcs/<slug>.md`。
- RFC 应包含：背景、目标、非目标、详细方案、备选方案对比、迁移与回滚、灰度策略、验收标准。
- **卡点**：等待用户审阅 RFC 并同意。

### 3-5. 连续执行：SPEC / Story / 测试用例
第 3、4、5 步**连续执行，不在中间向用户确认**，三份产物一并提交到第 6 步审查。

#### 3. 编写 SPEC（SDD：Spec-Driven Design）
- 在 `specs/<slug>.md` 输出技术规范文档。
- 内容包括：模块/接口契约、数据流、状态机、配置项、埋点、异常分支。
- 粒度细到可指导实现，但不写具体代码。

#### 4. 编写用户故事
- 在 `stories/<slug>.md` 输出用户故事。
- 每条故事采用 `As a / I want / So that` 格式，附明确验收标准（Given / When / Then）。
- 必须覆盖正向、删除/失败、边界场景。

#### 5. 编写测试用例（TDD）
- 按 TDD 先写测试用例。
- 单元测试与集成测试分目录组织。
- 测试此时应处于 RED 状态（实现未完成）。

### 6. 用户审查
- **卡点**：用户一次性审查第 3-5 步的全部三份产物（SPEC / Story / 测试用例）。同意后才能进入实现阶段。

### 7. 实现代码
- 按通过审查的 SPEC 编写实现，使测试转为 GREEN。
- 改动控制在 SPEC 范围内，超范围必须回到第 2 步走变更。

### 8. 回归与静态检查
- 跑通所有相关现存测试。
- 执行 `swift test`（单元 + 集成）/ `swift-format lint --recursive Sources tests`（静态检查）。
- 提交前自检 diff，确认无无关改动、无调试输出（如 `print`，自检 `--selftest` 除外）、无 TODO 残留。

### 9. E2E 验证（可选）
- 当影响首屏链路 / 跨模块协同 / 涉及用户感知关键路径时，必须增加 E2E 用例。
- GUI 走 XCUITest：`xcodegen generate && xcodebuild test -project agentmon.xcodeproj -scheme agentmonApp -destination 'platform=macOS'`（需 GUI 会话，通常在 CI 运行；本地仅能 `build-for-testing` 到编译级）。
- 跑通后输出验证报告。

### 10. 博客与文档沉淀
- 每个需求完成后，在 `blog/` 目录下按 LLM Wiki 的方式编写/更新相关博客和文档。
- 内容应包含：需求背景、技术方案要点、关键设计决策、踩坑记录、可复用经验。
- 文件命名：`blog/<slug>.md`，slug 与 RFC 保持一致。
- 目的：形成项目知识库，方便后续 Agent 或团队成员快速了解历史决策。
