# RFC: 菜单显示/隐藏桌宠 + 满级固定成熟形态

- **Slug**: `menu-toggle-and-mature-form`
- **状态**: Accepted（随实现一并沉淀）
- **作者**: agentmon team
- **日期**: 2026-08-04
- **关联**: 迭代自 [`multi-client-and-control-panel`](./multi-client-and-control-panel.md) · 复用 [`aurora-pet-and-interpolation`](../blog/aurora-pet-and-interpolation.md) 的皮肤展示通道
- **版本**: v0.8.0

---

## 1. 背景

两个体验缺口：

1. **状态栏菜单无法快速控制桌宠可见性**：显示/隐藏桌宠只能进「打开控制台 → 桌宠设置 → 显示」三步操作，菜单里没有一键开关。
2. **满级宠物无法定格喜欢的形态**：verdant 多形态包（蛋/幼体/青年/成熟）随等级 1:1 进化，宠物毕业（满级）后只能停在「成熟」。用户希望满级后能挑一个中意的成长形态固定展示，且明确「不再消耗或增长能量」。

## 2. 目标 / 非目标

### 2.1 目标
1. 状态栏菜单新增「显示/隐藏桌面宠物」开关，按当前可见性取反，与控制台开关、`app-settings.json` 三方同步。
2. 满级（毕业）宠物可在控制台「成长形态」卡片点选任一形态固定展示；固定期间能量永久冻结（不消耗/不增长），可一键恢复默认（成熟）。
3. 复用既有皮肤展示通道（`displaySkin`/`displayStage`/`suspend`），不新增持久化字段。

### 2.2 非目标
- 不改动能量/进化数值模型与毕业门槛。
- 不为未满级宠物开放固定形态（成长中形态跟随等级）。
- 不改动单形态元素包（aurora）的图鉴收藏交互。

## 3. 方案

### 3.1 菜单开关
`AppDelegate.menuNeedsUpdate` 在「打开控制台」与「退出」之间插入一项，标题按 `petPanel.isVisible` 取「隐藏/显示桌面宠物」，动作复用现有 `setPetVisible(_:)`（负责浮窗 orderFront/orderOut、`AppModel.petVisible`、`app-settings.json` 持久化三方同步）。

### 3.2 满级固定形态
- **复用皮肤通道**：满级宠物的物种已在 `graduated` 列表内，`displaySkin != nil` 时 `pump` 走 `engine.suspend`（只推进 lastTick，不结算能量/饥饿）→ 能量冻结。
- **新增** `MonitorCoordinator.pinDisplayStage(_:)`：仅当活跃宠物已毕业且在 `graduated` 内时生效；`stage` 非空即固定，`nil` 取消固定跟随成长。
- **渲染尊重固定形态**：`AppDelegate.currentStageID` 在皮肤态优先返回 `displayStage`，否则按等级推导（否则桌宠仍画等级形态，固定不生效）。
- **UI**：控制台「成长形态」卡片满级后各形态胶囊可点选，附「已固定：X」提示与「恢复默认（成熟）」按钮；仪表盘能量卡对多形态包显示「固定形态：X」。

## 4. 备选方案对比

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| A. 复用皮肤展示通道（选定） | 零新增持久化字段、暂停成长逻辑已测 | 活跃宠物借道「皮肤态」语义略绕 | ✅ 采纳 |
| B. 新增独立 `pinnedStage` 字段 | 语义清晰 | 新增状态/持久化/恢复/测试面更大；毕业本已冻结能量，冗余 | ❌ |

## 5. 迁移与回滚
- 无 schema 变更：`pinDisplayStage` 落到既有 `displaySkin`/`displayStage`，旧 `state.json` 天然兼容。
- 回滚：还原相关文件即可；已持久化的 `displaySkin`（满级物种）在 `restoreLifecycle` 内受 `graduated.contains` 守卫，回滚后自然回落活跃展示。

## 6. 验收标准
1. 菜单项标题随桌宠可见性正确切换，点击即时显示/隐藏并持久化。
2. 未满级宠物 `pinDisplayStage` 被忽略；满级固定后能量长时间空闲仍为冻结值。
3. 固定形态在桌宠浮窗与控制台一致生效；恢复默认回落成熟形态。
4. `swift build` / `swift test` / `swift-format lint` 全绿。
