# 满级却切不动：一条空 `graduated` 名单引出的图鉴、回填与能量条

> 需求 slug：`pet-gallery-energy-and-maxed-switch` ｜ 关联：迭代自 [`menu-toggle-and-mature-form`](./menu-toggle-and-mature-form.md) ｜ 版本：v0.9.0

三条反馈:要收藏 gallery、满级切不动、要能量条。第二条是这次真正有意思的 bug。

## 1. 满级却切不动:活体进化与持久化状态的错位

用户说「理论上已满级但不能切换」。翻 `state.json`:

```json
{ "level": 4, "graduated": [], "species": "", "energy": 2700 }
```

`level:4` ≥ 默认 `graduationLevel:4` → `engine.isGraduated == true`,确实满级。但 `graduated:[]` 是空的。而我上一版的 `pinDisplayStage` 守卫是:

```swift
guard let species = species, engine.isGraduated, graduated.contains(species) else { return false }
```

空名单 → `graduated.contains("")` 为 false → 直接忽略。**根因**:`graduated` 只在活体进化**跨越毕业阈值那一刻**由 `onGraduate` 追加。这只宠物是在更早的规则下（曾用更高的 graduationLevel、能量一路涨到 2700)达成满级的,恢复时 `engine.level` 已是 4,不会再触发那次「跨越」,于是名单永远为空。

活体事件流（一次性回调）与持久化快照（重启恢复）之间的经典错位:**依赖「转变时刻」记录的状态,遇到「加载既有状态」就漏了**。

两处修:
- 守卫放宽——活跃宠物**满级即可**固定/切换,不再要求已在收藏名单(收藏名单是「其他已解锁物种皮肤」的概念,不该卡住当前这只)。
- `restoreLifecycle` **回填**——加载时若 `isGraduated` 且当前物种不在名单,补记进去,让展示态也能跨重启持久化。幂等、无外部依赖,顺带修好所有历史存档。

## 2. 图鉴 gallery:缩略图不额外出美术

verdant 是一只角色 × 4 形态(蛋/幼体/青年/成熟),没有静态立绘。gallery 要缩略图怎么办?——直接取每个形态 `idle` 动画条的**首帧**:`store.frames(idle).first` → `NSImage(cgImage:)`,面板打开时构建一次塞进 `AppModel.forms`。已解锁下标 = `min(stageCount-1, displayLevel)`,满级即全解锁;当前展示描边、未解锁去饱和置灰、满级其余标「可固定」点选即切换。

## 3. 能量条:满级不要显示会溢出的原始值

桌宠浮窗加一条自绘胶囊进度条。坑在满级:`energy=2700` 而 `energyToNext=threshold(4)=1000`,直接画会溢出。故 `maxed = isGraduated || isSkin` 时画满格黄条 +「满级 ✓」,成长中才画 `energy/energyToNext` 绿条。`PetState` 补一个 `isGraduated` 由快照灌入即可。

## 4. 门禁与发布

新增 2 条回归测试锁住「空 graduated 也能 pin」「固定态重启还原」。`swift build` / `swift test`(120 通过)/ `swift-format lint --strict` 全绿,推 main + tag `v0.9.0`,由 GitHub Actions 产出正式包安装。

**经验**:一次性事件回调负责「转变」,但凡有持久化恢复路径,就要在**加载态**里补一遍不变量校验/回填——否则历史数据会以你没预期的形态回来找你。
