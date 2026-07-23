# E2E（XCUITest）场景 —— Step 9 落地

E2E 属工作流第 9 步（可选、影响用户感知关键路径时必做）。本文件先固化场景，实现阶段用
XCUITest 编写并跑通后输出验证报告。运行方式：`xcodebuild test -scheme agentmon`（含 `agentmonUITests`）。

## 关键路径场景

### E2E-1 菜单栏三态实时反映
1. 启动 App（测试模式：spool 目录指向临时路径，绕过真实 Claude）。
2. 向 spool 投递 `UserPromptSubmit` 事件 → 菜单栏「工作中」显示 1。
3. 投递 `Notification` → 转「等待中」1、「工作中」0。
4. 投递 `Stop` → 「已完成」+1、宠物播放庆祝。

### E2E-2 宠物窗口存在与互动
1. 开启宠物窗 → 断言浮窗出现、置顶、点击不抢焦点。
2. 点击「撸猫」→ 断言出现互动反应。

### E2E-3 进化换肤演出
1. 测试模式注入接近门槛的能量与一次完成事件 → 断言触发进化动画、皮肤切到 Lv2、菜单栏 `Lv2`。

### E2E-4 启用/停用 Claude 集成（指向临时 settings.json）
1. 点击「启用集成」→ 断言临时 settings.json 含 agentmon hooks、生成备份。
2. 点击「停用集成」→ 断言仅移除 agentmon 项、用户既有 hooks 保留。

## 测试可控性要求（供实现参考）
- App 需支持通过环境变量/启动参数覆盖：spool 目录、Application Support 目录、Claude settings 路径，
  以便 UI 测试在隔离沙盒中运行，绝不触碰用户真实数据。
- 能量/门槛可由测试注入的 `config.json` 控制，便于制造「即将进化」态。
