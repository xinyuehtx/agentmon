# User Stories: 菜单显示/隐藏桌宠 + 满级固定成熟形态

- **Slug**: `menu-toggle-and-mature-form`
- **对应**: [`rfcs/menu-toggle-and-mature-form.md`](../rfcs/menu-toggle-and-mature-form.md) · [`specs/menu-toggle-and-mature-form.md`](../specs/menu-toggle-and-mature-form.md)

覆盖正向、失败/边界场景。验收标准用 Given / When / Then。

---

## Epic A：菜单一键显示/隐藏桌宠

### US-A1 从菜单隐藏桌宠（正向）
**As a** 需要临时清屏的开发者
**I want** 在状态栏菜单一键隐藏桌面宠物
**So that** 不必进控制台三步操作

- **Given** 桌宠当前可见
- **When** 我点开状态栏菜单，项显示「隐藏桌面宠物」并点击
- **Then** 桌宠浮窗立即隐藏，`app-settings.json` 的 `petVisible` 置 `false`，控制台开关同步为关

### US-A2 从菜单显示桌宠（正向）
- **Given** 桌宠当前隐藏
- **When** 菜单项显示「显示桌面宠物」并点击
- **Then** 桌宠浮窗立即显示，`petVisible` 置 `true`，控制台开关同步为开

### US-A3 标题随状态切换（边界）
- **Given** 桌宠可见性在菜单外被改变（如控制台开关）
- **When** 我再次打开状态栏菜单
- **Then** 菜单项标题反映最新可见性（显示/隐藏互斥、不陈旧）

## Epic B：满级固定成熟形态

### US-B1 满级固定喜欢的形态（正向）
**As a** 养成到毕业的用户
**I want** 把满级宠物定格在我喜欢的成长形态
**So that** 桌宠一直是我中意的样子

- **Given** 活跃宠物已满级（毕业）且为多形态包
- **When** 我在控制台「成长形态」点选某一形态
- **Then** 桌宠浮窗与控制台立即切换为该形态，卡片显示「已固定：X」

### US-B2 固定期间能量冻结（正向）
- **Given** 宠物已固定某形态
- **When** 长时间无任务空闲
- **Then** 能量既不衰减也不增长（冻结），桌宠不改变形态

### US-B3 恢复默认成熟形态（正向）
- **Given** 宠物已固定非成熟形态
- **When** 我点「恢复默认（成熟）」
- **Then** 退出固定态、回落成熟形态；「恢复默认」按钮在未固定时禁用

### US-B4 未满级不可固定（失败/边界）
- **Given** 活跃宠物尚未满级
- **When** 我尝试点选形态
- **Then** 点击被忽略（`isGraduated` 门控），成长形态仍跟随等级

### US-B5 单形态包无此入口（边界）
- **Given** 使用单形态元素包（aurora，无 stages）
- **When** 打开桌宠设置
- **Then** 不出现「成长形态」卡片，元素图鉴收藏交互不受影响
