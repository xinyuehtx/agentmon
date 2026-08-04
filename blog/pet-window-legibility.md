# 桌宠浮窗可读性:去掉情绪文案 + 黑底白字

> 需求 slug：`pet-window-legibility` ｜ 关联：迭代自 [`pet-gallery-energy-and-maxed-switch`](./pet-gallery-energy-and-maxed-switch.md) ｜ 版本：v0.9.1

两条小诉求:桌宠上的「收藏/发呆」等情绪文案去掉;其余文字要黑底白字,在任意壁纸下都看得清。

## 改动

- **去情绪文案**:移除浮窗中的状态行(原「Lv0 · 发呆」/「收藏 · 发呆」)与角标里的「收藏」字样。角标统一显示 `Lv{n}`。相应删掉不再使用的 `moodText`。
- **黑底白字**:
  - 等级角标:黑色胶囊底(不透明度 0.45→0.7)+ 白字。
  - 计数(▶⏸✓)+ 能量条:整体包一层黑色圆角底(不透明度 0.6),文字改白色;能量条轨道从 `primary.opacity(0.15)` 改 `white.opacity(0.22)`,在黑底上可见。

## 保住 E2E 的小心思

`PetPanelUITests` 靠 `staticTexts["pet.state"].value == "<mood>:<level>"`(如 `working:1`)断言状态。删掉可见状态行后,把 `pet.state` 的 `accessibilityIdentifier` + `accessibilityValue` **迁到等级角标**上——角标可见文字是 `Lv0`,但 `AXValue` 仍是 `working:1`,测试读的是 value,链路不破。120 条测试 + `--strict` lint 全绿。

**经验**:删 UI 文案前先查无障碍锚点被谁依赖;把 identifier/value 迁到另一个常驻可见元素,比留一个隐藏空 `Text` 更稳(零尺寸/隐藏元素在 XCUITest 里可能寻址不到)。
