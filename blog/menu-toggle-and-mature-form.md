# 菜单一键隐藏桌宠 + 满级定格成熟形态：复用皮肤通道的最小改动

> 需求 slug：`menu-toggle-and-mature-form` ｜ 关联：迭代自 [`multi-client-and-control-panel`](./multi-client-and-control-panel.md) · 复用 [`aurora-pet-and-interpolation`](./aurora-pet-and-interpolation.md) ｜ 版本：v0.8.0

两个小而实在的体验诉求：状态栏菜单能一键显示/隐藏桌宠；满级宠物能挑一个中意的成长形态定格、且明确不再消耗或增长能量。本文沉淀这次「用尽量少的新状态解决问题」的取舍。

## 1. 菜单开关：不要造新状态，复用已有三方同步

显示/隐藏桌宠的真身早就存在——`setPetVisible(_:)` 负责浮窗 `orderFront/orderOut`、`AppModel.petVisible` 与 `app-settings.json` 三方同步。菜单缺的只是一个入口。

`menuNeedsUpdate` 每次弹出都重建菜单项，天然适合放**动态标题**：读 `petPanel.isVisible` 取反命名「隐藏/显示桌面宠物」，点击回到 `setPetVisible`。没有第二处真相，也就没有 UI 与设置漂移。

## 2. 满级定格形态：毕业其实已经冻结了能量

verdant 是「一只角色 × 4 形态（蛋/幼体/青年/成熟）」，等级与形态 1:1，升级即进化。用户要的是**满级后挑一个形态定格**。

第一反应是加个 `pinnedStage` 字段，但翻代码发现两件事：

- **毕业本就冻结能量**：`EnergyEngine.tick` 开头 `guard !isGraduated else { return }`——满级宠物早就不成长/不衰减/不饥饿。「不消耗或增长能量」这条已经天然满足。
- **皮肤展示通道正是「暂停成长 + 展示指定形态」**：aurora 收藏皮肤用的 `displaySkin`/`displayStage` + `engine.suspend`，语义与需求完全重合。满级宠物的物种已进入 `graduated` 列表，借道它天经地义。

于是新增的只有一个方法 `pinDisplayStage(_:)`：满级且已毕业才生效，非空即固定、`nil` 即恢复。零新增持久化字段，`restoreLifecycle` 的 `graduated.contains` 守卫顺带保证重启恢复安全。

## 3. 一个隐蔽的坑：渲染没有尊重固定形态

固定逻辑写完，桌宠却仍画等级推导的「成熟」。定位到 `AppDelegate.currentStageID`——它只按 `displayLevel → stageIndex` 算形态，无视 `displayStage`。而 `petState.stage = currentStageID(snap) ?? snap.displayStage`，`currentStageID` 对多形态包永远非空，`snap.displayStage` 这个兜底根本轮不到。

修法一行：皮肤态下若 `stageIDs` 含 `displayStage` 就优先返回它。顺带把仪表盘能量卡对多形态包的文案从「展示：极光罗盘猫」（空物种误命中 aurora 默认名）改成「固定形态：青年」。

## 4. 门禁与验证

新增 3 条集成测试锁住边界：未满级忽略、满级固定后空闲 1000 分钟能量仍冻结、取消固定回落。`swift build` / `swift test`（118 通过）/ `swift-format lint --strict` 全绿，交由 GitHub Actions（macos-14：build·test·lint + XCUITest + 打包）产出正式包。

**经验**：动手加字段前先读一遍现有状态机——这次「毕业已冻结能量」「皮肤通道即暂停成长」两个既有事实，把一个看似要新增状态的需求压成了一个方法 + 一行渲染修正。
