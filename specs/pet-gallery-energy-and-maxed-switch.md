# SPEC: 成长形态图鉴 gallery + 满级可切换修复 + 桌宠能量条

- **Slug**: `pet-gallery-energy-and-maxed-switch`
- **对应**: [`rfcs/pet-gallery-energy-and-maxed-switch.md`](../rfcs/pet-gallery-energy-and-maxed-switch.md)
- **版本**: v0.9.0

---

## 1. 接口契约

### 1.1 `MonitorCoordinator.pinDisplayStage(_:) -> Bool`（放宽）
- 前置：`species != nil && engine.isGraduated`（**移除** `graduated.contains` 要求）。
- 行为不变：非空固定 `displaySkin=species; displayStage=stage`；`nil` 取消固定。

### 1.2 `MonitorCoordinator.restoreLifecycle(...)`（回填）
- 设 `self.species/graduated/diedSpecies` 后：
  ```
  if let s = species, engine.isGraduated, !graduated.contains(s) { graduated.append(s) }
  ```
- 展示皮肤恢复守卫改用回填后的 `self.graduated.contains(skin)`。

### 1.3 `AppModel.forms: [PetFormInfo]`（新增）
- `PetFormInfo { id: String; name: String; thumbnail: NSImage? }`。
- 由 `AppDelegate.refreshModelSettings`（面板打开）赋值一次：`stageIDs.map { PetFormInfo(id,name,stageThumbnail(id)) }`。

### 1.4 `AppDelegate.stageThumbnail(_:) -> NSImage?`（新增）
- 取 `actions(forStage:)["idle"] ?? 任一`，`store.frames(a).first` → `NSImage(cgImage:)`；缺失返回 `nil`。

### 1.5 `PetState.isGraduated: Bool`（新增）
- `updateUI` 灌入 `snap.isGraduated`。

### 1.6 `RasterPetView.energyBar`（新增）
- `maxed = isGraduated || isSkin`；`frac = maxed ? 1 : clamp(energy/max(1,energyToNext))`。
- 自绘：胶囊底 + 填充（maxed 黄、否则绿）+ 文案（maxed「满级 ✓」/否则 `energy/total`）。
- 无障碍：id `pet.energy`，value `maxed`/`e:t`。

## 2. 数据流
```
面板打开 → refreshModelSettings → forms = stageIDs.map{thumbnail}
每次 pump → updateUI → petState.isGraduated = snap.isGraduated → energyBar 刷新
点选形态(仅满级) → onSelectStage(id) → pinDisplayStage(id) → suspend(冻结) → snapshot
启动恢复 → restoreLifecycle 回填 graduated → 满级即可 pin / 展示态可还原
```

## 3. 视图规格（ControlPanelView.stageGallery）
- 标题：`成长形态图鉴（reached+1/total）`，`reached = min(stageCount-1, displayLevel)`。
- `LazyVGrid` 4 列 × `FormCell`：
  - `reached = idx <= reachedIndex`；`isCurrent = form.id == currentStage`；`tappable = isGraduated`。
  - 未解锁：置灰 + 去饱和 + 「未解锁」；当前：绿描边 +「展示中」；满级其余：「可固定」。
  - `onTapGesture`：`tappable && reached` 才触发 `onSelectStage(id)`。
- 满级底部：`已固定：X`（isSkinMode 时）+ `恢复默认（成熟）` 按钮（`disabled(!isSkinMode)`）。
- 兜底：`model.forms` 空时按 `stages` 生成无图占位（`FormCell` 缩略图 nil → leaf 占位）。

## 4. 异常分支
- 单形态包（`stages` 空）：不渲染 gallery，元素图鉴不变。
- 缩略图渲染失败：`thumbnail=nil` → 占位图标，不崩溃。
- 未满级点选：UI `tappable=false` + 核心 `pinDisplayStage` 双重忽略。
