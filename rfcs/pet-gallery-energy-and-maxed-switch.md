# RFC: 成长形态图鉴 gallery + 满级可切换修复 + 桌宠能量条

- **Slug**: `pet-gallery-energy-and-maxed-switch`
- **状态**: Accepted（随实现一并沉淀）
- **作者**: agentmon team
- **日期**: 2026-08-04
- **关联**: 迭代自 [`menu-toggle-and-mature-form`](./menu-toggle-and-mature-form.md)
- **版本**: v0.9.0

---

## 1. 背景

上一版落地「满级固定成熟形态」后收到三条反馈：

1. **需要收藏 gallery**：希望以图鉴（缩略图）形式看到全部成长形态与解锁情况，而非纯文字进度条。
2. **满级却切换不了**（Bug）：实测 `state.json` 为 `level:4`（已满级）但 `graduated:[]` 为空，`species:""`。`pinDisplayStage` 要求 `graduated.contains(species)`，空名单 → 直接被忽略。根因：`graduated` 只在**活体进化跨越毕业阈值那一刻**追加；旧规则下（曾用更高 graduationLevel）达成的满级宠物重启恢复后不在名单内。
3. **需要能量条**：桌宠浮窗只有等级/情绪/计数，看不到当前能量进度。

## 2. 目标 / 非目标

### 2.1 目标
1. 控制台「成长形态图鉴」以缩略图 gallery 呈现全部形态：已解锁高亮、当前展示描边、满级可点选固定。
2. 修复满级不可切换：活跃宠物**满级即可固定/切换**，不再要求已在收藏名单；恢复时对满级活跃物种**回填**收藏，保证展示态可持久化。
3. 桌宠浮窗新增能量条：成长中显示 `energy/energyToNext`，满级显示满格「满级」。控制台仪表盘满级也补满格条。

### 2.2 非目标
- 不改能量/进化数值与毕业门槛。
- 不为单形态元素包（aurora）改动既有元素图鉴收藏交互。
- 缩略图不额外出美术，直接取各形态 `idle` 动画首帧。

## 3. 方案

- **Bug 修复**（Core）：`pinDisplayStage` 守卫由 `species!=nil && isGraduated && graduated.contains` 放宽为 `species!=nil && isGraduated`；`restoreLifecycle` 增加回填：`if isGraduated && !graduated.contains(species) { graduated.append(species) }`，随后再判定展示皮肤恢复。
- **Gallery**（App）：`AppModel.forms:[PetFormInfo]`（id/名/缩略图 NSImage），面板打开时由 `AppDelegate.stageThumbnail`（`idle` 首帧）构建一次；`ControlPanelView` 以 `LazyVGrid` + `FormCell` 渲染，已解锁下标 = `min(stageCount-1, displayLevel)`。
- **能量条**（App）：`PetState.isGraduated` 由快照灌入；`RasterPetView.energyBar` 自绘胶囊进度条（满级/收藏满格黄条）。

## 4. 备选方案对比

| 议题 | 选定 | 备选 | 理由 |
|---|---|---|---|
| 满级切换守卫 | 放宽为 isGraduated + 恢复回填 | 迁移脚本重算 graduated | 回填零外部依赖、幂等、覆盖旧状态 |
| 缩略图来源 | idle 首帧动态渲染 | 额外出静态立绘 | 无需新素材、随包一致 |

## 5. 迁移与回滚
- 无 schema 变更。回填在内存态完成，下次 `persist()` 落盘即修正 `graduated`。
- 回滚：还原文件即可；已回填的 `graduated` 项不影响旧版本读取（旧版本忽略未知即可）。

## 6. 验收标准
1. 满级但 `graduated` 空的宠物可固定/切换形态且能量冻结（新增回归测试）。
2. 图鉴 gallery 正确显示解锁/当前/可固定态；满级点选即切换、可恢复默认。
3. 桌宠浮窗与仪表盘均可见能量条；满级显示满格。
4. `swift build` / `swift test`（120 通过）/ `swift-format lint --strict` 全绿。
