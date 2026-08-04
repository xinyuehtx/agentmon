# User Stories: 成长形态图鉴 gallery + 满级可切换修复 + 桌宠能量条

- **Slug**: `pet-gallery-energy-and-maxed-switch`
- **对应**: [`rfcs/pet-gallery-energy-and-maxed-switch.md`](../rfcs/pet-gallery-energy-and-maxed-switch.md) · [`specs/pet-gallery-energy-and-maxed-switch.md`](../specs/pet-gallery-energy-and-maxed-switch.md)

覆盖正向、失败/边界。验收用 Given / When / Then。

---

## Epic A：成长形态图鉴（收藏 gallery）

### US-A1 以图鉴看收藏（正向）
**As a** 养成桌宠的用户
**I want** 用缩略图图鉴看到全部成长形态与解锁情况
**So that** 一眼看清养到哪一步、还差哪些

- **Given** 使用多形态包（verdant）
- **When** 打开控制台「桌宠设置」
- **Then** 看到「成长形态图鉴（n/总数）」网格：已解锁高亮、当前展示描边、未解锁置灰标「未解锁」

### US-A2 满级点选固定（正向）
- **Given** 宠物已满级
- **When** 在图鉴点选某形态
- **Then** 桌宠切换为该形态、能量冻结，卡片标「展示中」，底部「已固定：X」

### US-A3 恢复默认（正向）
- **Given** 已固定非成熟形态
- **When** 点「恢复默认（成熟）」
- **Then** 回落成熟形态；未固定时按钮禁用

## Epic B：满级可切换修复

### US-B1 旧满级存档也能切换（回归）
**As a** 早前已把宠物养到满级的用户
**I want** 即使收藏名单为空也能切换/固定形态
**So that** 不因历史数据缺失而卡住

- **Given** `state.json` 为满级（level≥毕业阈值）但 `graduated` 为空
- **When** 启动 agentmon 并在图鉴点选形态
- **Then** 恢复时自动回填收藏、点选立即生效且能量冻结

### US-B2 固定态跨重启保留（正向）
- **Given** 满级并固定了某形态
- **When** 重启 agentmon
- **Then** 仍展示该固定形态（凭回填后的收藏名单还原）

## Epic C：桌宠能量条

### US-C1 看当前能量（正向）
**As a** 用户
**I want** 在桌宠浮窗直接看到能量条
**So that** 不用打开控制台就知道进度

- **Given** 宠物成长中
- **When** 桌宠浮窗显示
- **Then** 出现能量条 `energy/energyToNext`，随任务实时变化

### US-C2 满级显示满格（边界）
- **Given** 宠物已满级或正展示固定形态
- **When** 查看能量条
- **Then** 显示满格黄条 +「满级 ✓」，不显示会溢出的原始数值
