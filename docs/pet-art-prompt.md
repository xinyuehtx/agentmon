# 宠物美术 · 生图 AI 提示词

用于让文生图 AI 产出**风格一致、可切片**的原创宠物帧图集；回传后由 agentmon 切片去背拼成动图。

> 你只需填「元素 + 动物」（可选阶段/动作）。所有提示词**强制原创**——不得像任何既有游戏/动画角色。

---

## 通用风格块（两个模板共用，勿改）

```
STYLE: cute chibi mascot creature, original design, thick clean black outline,
soft cel shading, big expressive eyes, simple rounded shapes, flat 2D game sprite,
vibrant colors, centered, full body, front view.
CONSISTENCY: exactly the same character in every cell — identical colors, markings,
proportions and outline.
BACKGROUND: solid flat magenta #FF00FF, no gradient, no shadow, no floor.
LAYOUT: evenly spaced grid, equal square cells, no gaps, no borders, no text, no numbers, no watermark.
ORIGINAL: must NOT resemble Pokémon or any existing franchise/character.
```

## 模板 A —— 进化图鉴（先跑，锁定形象）

填 `{ANIMAL}` `{ELEMENT}`。一张图 = 4 个进化阶段并排。

```
A horizontal strip of 4 cells, same original {ELEMENT}-type {ANIMAL} creature evolving
left to right: [egg] a speckled {ELEMENT} egg; [juvenile] tiny baby form;
[mature] bigger form with clear {ELEMENT} feature; [final] largest powerful form.
<STYLE block here>
Cell size 512x512, final image 2048x512.
```

## 模板 B —— 动作帧条（每个动作跑一次，用于拼动图）

填 `{ANIMAL}` `{ELEMENT}` `{STAGE}` `{ACTION}`（动作见下表）。一张图 = 一个动作的 6 帧。

```
A horizontal sprite strip of 6 frames animating ONE action of the SAME original
{ELEMENT}-type {ANIMAL} creature ({STAGE} form). Action: {ACTION}.
Frames are keyframes of the motion in order, left to right, character centered
and identical scale in every frame.
<STYLE block here>
6 equal cells, cell 512x512, final image 3072x512.
```

### `{ACTION}` 取值（逐个跑）

| 状态 | ACTION 文案 |
| --- | --- |
| idle | `gentle idle breathing, slight body bob, one blink` |
| working | `attacking, lunging forward and shooting a {ELEMENT} attack (water: water jet/bubbles; fire: fire sparks; grass: leaf blades) toward the right` |
| waiting | `waving one arm and doing a happy little jump` |
| complete | `celebrating, jumping with both arms up, sparkles` |

---

## 填好的例子（water + otter，模板 B / 攻击）

```
A horizontal sprite strip of 6 frames animating ONE action of the SAME original
water-type otter creature (mature form). Action: attacking, lunging forward and
shooting a water jet toward the right.
Frames are keyframes of the motion in order, left to right, character centered
and identical scale in every frame.
STYLE: cute chibi mascot creature, original design, thick clean black outline, soft
cel shading, big expressive eyes, simple rounded shapes, flat 2D game sprite, vibrant
colors, centered, full body, front view.
CONSISTENCY: exactly the same character in every cell — identical colors, markings,
proportions and outline.
BACKGROUND: solid flat magenta #FF00FF, no gradient, no shadow, no floor.
LAYOUT: evenly spaced grid, equal square cells, no gaps, no borders, no text, no numbers, no watermark.
ORIGINAL: must NOT resemble Pokémon or any existing franchise/character.
6 equal cells, cell 512x512, final image 3072x512.
```

## Negative prompt（支持负面词的模型都加）

```
text, numbers, watermark, signature, border, frame lines, gradient background,
drop shadow, ground shadow, blurry, jpeg artifacts, multiple different characters,
inconsistent design, extra limbs, realistic, 3d render, photo
```

## 跨图一致性技巧（关键）

- 先跑**模板 A** 定稿形象；再跑模板 B 时用模型的「角色一致」功能：
  - Midjourney：`--cref <A图URL>`
  - SD / Flux：**同一 seed + image-to-image / IP-Adapter**
  - GPT-4o / Nano-Banana：直接「保持这只角色不变，只改动作」
- 一次只生成**一个动作**（6 帧同一动作），比一张大网格塞多动作稳得多。

---

## 回传规范（这样能直接接入）

1. 格式：**PNG**（优先透明背景；否则用纯 `#FF00FF` 底，由 agentmon 抠图）。**不要 GIF / JPEG**。
2. 命名：`{animal}_{element}_{stage}_{action}.png`，例：`otter_water_mature_attack.png`。
3. 每个动作一张 6 帧横条；四阶段（egg/juvenile/mature/final）齐了更好。

## agentmon 侧接入（待素材到位后）

- 新增**光栅精灵图集播放**通路：切片 → 去背/裁边 → 按 fps 逐帧播放；与现有矢量宠物并存。
- `assets/pets.json` 按物种标注渲染方式：`vector`（现有程序化）或 `sheet`（图集帧）。
- 先给 1–2 张跑通管线，再批量接入。
