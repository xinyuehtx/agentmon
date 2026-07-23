# 宠物美术 · 生图 AI 提示词

让文生图 AI 产出**风格一致、可切片**的原创宠物动画帧；回传后由 agentmon 切片、抠底、对齐、拼成逐帧动画。

> 你只填「元素 + 动物」。所有提示词**强制原创**——不得像任何既有游戏/动画角色。
> 帧越多越平滑：**推荐每个动作 30 帧**（最少 8）。

---

## 通用风格块（所有模板共用，勿改）

```
STYLE: cute chibi mascot creature, original design, thick clean black outline,
soft cel shading, big expressive eyes, simple rounded shapes, flat 2D game sprite,
vibrant colors, centered, full body, front view.
CONSISTENCY: EXACTLY the same character in every frame — identical colors, markings,
proportions, outline and size. Only the pose/motion changes between frames.
BACKGROUND: solid flat magenta #FF00FF, no gradient, no shadow, no floor, no divider lines.
ORIGINAL: must NOT resemble Pokémon or any existing franchise/character.
```

## 模板 A —— 进化图鉴（先跑，锁定形象）

填 `{ANIMAL}` `{ELEMENT}`。一张图 = 4 阶段并排。

```
A horizontal strip of 4 cells, same original {ELEMENT}-type {ANIMAL} creature evolving
left to right: [egg] a speckled {ELEMENT} egg; [juvenile] tiny baby form;
[mature] bigger form with clear {ELEMENT} feature; [final] largest powerful form.
<STYLE block>
```

## 模板 B —— 动作动画条（每个动作跑一次；**推荐 30 帧**）

填 `{ANIMAL}` `{ELEMENT}` `{STAGE}` `{ACTION}` `{N}`（N=30）。一张图 = 一个动作的 N 帧。

```
A horizontal sprite sheet: {N} equal cells in ONE row, showing the SAME original
{ELEMENT}-type {ANIMAL} creature ({STAGE} form) performing ONE smooth action: {ACTION}.
The {N} frames are EVENLY-TIMED keyframes of the motion in order left to right,
INCLUDING the in-between poses (not just start and end), so the sequence plays smoothly.
For looping actions the last frame flows seamlessly back into the first.
Character centered and identical scale in every cell.
<STYLE block>
Aspect ratio 30:9, high resolution.
```

**`{ACTION}` 文案**（逐个跑；`complete` 为一次性，其余循环）：
| 状态 | ACTION 文案 |
| --- | --- |
| idle | `gentle idle loop: breathing, small body bob, occasional blink; seamless loop` |
| working | `attack loop: wind up, lunge forward and shoot a {ELEMENT} attack (water: water jet/bubbles; fire: fire sparks; grass: leaf blades), recoil back; seamless loop` |
| waiting | `waiting loop: happy wave with one arm and a little jump; seamless loop` |
| complete | `one-shot celebration: crouch, jump up with both arms, sparkles, land` |

## Negative prompt（支持负面词的模型都加）

```
text, numbers, watermark, signature, border, frame lines, divider lines, grid lines,
gradient background, drop shadow, ground shadow, blurry, jpeg artifacts,
multiple different characters, inconsistent design, size jumps between frames,
extra limbs, realistic, 3d render, photo
```

## 跨帧一致性技巧（帧越多越关键）

- 先跑**模板 A** 定稿形象；再跑 B 时用「角色一致」功能保持同一只：
  Midjourney `--cref <A图URL>`；SD/Flux **同一 seed + IP-Adapter/image-to-image**；
  GPT-4o / Nano-Banana 直接「保持这只角色完全不变，只改动作，输出 30 帧一行」。
- **一次只生成一个动作**（同一动作的 N 帧），比一张图塞多动作稳得多。
- 若模型输出宽度受限（塞不下 30 帧还清晰）：降到 **8 帧**，或用下面的「独立帧 / 动图」方式。

---

## 可选：直接产出「更多图 / 动图」

除了单张多帧条，这两种我也能接（回传后我来处理）：

### 方式 ① 独立帧（每帧一张，分辨率最高）
- 让模型对同一动作输出 **N 张独立图**，每张是第 k 帧姿势，用角色一致功能保持同一只。
- 命名：`{animal}_{element}_{stage}_{action}_01.png` … `_30.png`（两位序号，按顺序）。

### 方式 ② 动图（视频/动画模型）
- 用图生视频模型（如 Runway / Kling / Pika / Luma / Sora）：把模板 A 的定妆图作为首帧，
  提示：`the creature performs <ACTION>, seamless loop, static camera, plain solid magenta background, no camera move`。
- 导出 **GIF 或 MP4**（1–2 秒，循环）。命名同上：`{animal}_{element}_{stage}_{action}.gif`。
- 注意：视频模型难保证干净透明底与完美循环，一致性也可能漂移；**若要最稳的透明循环，仍首选「模板 B 多帧条」**。

---

## 回传规范（这样我能直接接入）

1. 首选 **PNG 多帧条**（模板 B）；也接 **独立帧 PNG 序列** 或 **GIF/MP4**。
2. 背景：优先透明；否则用纯 `#FF00FF` 洋红底（我来抠）。
3. 命名：`{animal}_{element}_{stage}_{action}[...]`，四阶段（egg/juvenile/mature/final）齐全更好。
4. **告诉我每个动作的帧数**（例如 30）。

## agentmon 侧接入

- 多帧条：`swift scripts/process-packs.swift <源目录> [帧高=160]`。
  **帧数自动检测**：抠底去分隔线后，用「空隙分行 + 列内容自相关求每行帧数」，单行横条、R×C 网格、
  带特效/缺帧的行都能正确切分；fps 按「一轮秒数」推导，帧越多越平滑而非越慢。
  个别非周期序列（如某个孵化图）若检测偏 ±1 帧，在脚本顶部 `layoutOverride` 里按文件名写死列数即可。
- 独立帧序列 / GIF：告诉我格式，我给 `process-packs.swift` 加对应读取（GIF 用 CGImageSource 逐帧读，序列用序号拼装），很快。
- App 与网页预览自动按 manifest 的帧数播放，并做交叉溶解补帧。
