# SPEC: 菜单显示/隐藏桌宠 + 满级固定成熟形态

- **Slug**: `menu-toggle-and-mature-form`
- **对应**: [`rfcs/menu-toggle-and-mature-form.md`](../rfcs/menu-toggle-and-mature-form.md)
- **版本**: v0.8.0

---

## 1. 模块与接口契约

### 1.1 `MonitorCoordinator.pinDisplayStage(_:) -> Bool`（新增）
```
@discardableResult
func pinDisplayStage(_ stage: String?) -> Bool
```
- **前置**：`species != nil` 且 `engine.isGraduated` 且 `graduated.contains(species)`；不满足返回 `false` 且不改状态。
- **行为**：
  - `stage` 非空 → `displaySkin = species; displayStage = stage`（进入皮肤态）。
  - `stage == nil` → `displaySkin = nil; displayStage = nil`（退出皮肤态，跟随成长）。
- **副作用**：皮肤态下 `pump` 走 `engine.suspend(now:)` → 能量/饥饿不结算（冻结）。
- **返回**：是否生效。

### 1.2 `AppDelegate.currentStageID(_:) -> String?`（修改）
- 有 `stageIDs` 时：若 `snap.isSkinMode` 且 `stageIDs.contains(snap.displayStage)` → 返回 `snap.displayStage`；否则按 `displayLevel → stageIndex` 推导。
- 无 `stageIDs`（单形态包）→ 返回 `nil`。

### 1.3 `AppDelegate.menuNeedsUpdate(_:)`（修改）
- 菜单项顺序：`打开控制台…` → `显示/隐藏桌面宠物`（标题按 `petPanel.isVisible ?? appSettings.petVisible` 取反命名）→ 分隔线 → `退出 agentmon`。
- 新增 `@objc togglePetFromMenu()`：读当前可见性取反后调用 `setPetVisible(_:)`。

### 1.4 `AppModel.onSelectStage: ((String?) -> Void)?`（新增回调）
- UI 点选形态 → `onSelectStage?(stage)`；恢复默认 → `onSelectStage?(nil)`。
- `AppDelegate.wireModel` 接线到 `selectStage(_:)` → `coordinator.pinDisplayStage(_:)` + `pump()`。

## 2. 数据流
```
控制台点选形态 ──onSelectStage(stage)──▶ AppDelegate.selectStage
   └─▶ coordinator.pinDisplayStage(stage) ─(满级)─▶ displaySkin/displayStage 置位
        └─▶ pump() ─▶ engine.suspend（能量冻结）─▶ snapshot(isSkinMode,displayStage)
             ├─▶ updateUI: petState.stage = currentStageID(snap)（尊重固定形态）
             └─▶ feedDashboard: model.currentStage / isSkinMode / displayStage
菜单点选 ──togglePetFromMenu──▶ setPetVisible(!visible) ─▶ 浮窗 + AppModel + app-settings.json
```

## 3. 状态机（活跃宠物展示态）
```
[成长中] --升级--> [成长中] --毕业(满级)--> [满级·成熟(默认)]
[满级·成熟] --pinDisplayStage(x)--> [满级·固定形态 x, 能量冻结]
[满级·固定形态] --pinDisplayStage(nil)--> [满级·成熟(默认)]
未满级 --pinDisplayStage(*)--> (忽略, 无变化)
```

## 4. 配置项
- 无新增配置/持久化字段。复用 `PersistentState.displaySkin` / `displayStage`，经 `restoreLifecycle` 的 `graduated.contains` 守卫恢复。

## 5. 异常分支
- 未满级点选：`pinDisplayStage` 返回 `false`，UI 层已由 `model.isGraduated` 门控点击，双重保险。
- `displayStage` 不在 `stageIDs`：`currentStageID` 回落等级推导，避免渲染空动作集。
- 单形态包（aurora）：`stageIDs` 空 → 成长形态卡片不渲染，行为不变。

## 6. 埋点/日志
- 复用现有 `pet` 域日志；固定/恢复不新增强制日志（避免噪声）。
