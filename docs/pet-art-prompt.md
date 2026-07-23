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

> ⚠ **流水线当前的原生输入是「独立帧序列」（见下方方式 ①），不是这里的单张多帧条。**
> 多帧条需先自行切成独立帧再回传；且实践中「一行 N 格」的提示常被模型误画成「一排多只主体」，
> 反而更不稳。除非你的模型只擅长出条图，否则**优先用方式 ①**。

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

## 推荐：独立帧 / 动图

这两种回传后我直接接入；**方式 ① 是流水线的原生输入，最推荐**：

### 方式 ① 独立帧（每帧一张，分辨率最高，**推荐**）
- 让模型对同一动作输出 **N 张独立图**，每张是第 k 帧姿势，用角色一致功能保持同一只。
- 命名：`{animal}_{element}_{stage}_{action}_01.png` … `_30.png`（两位序号，按顺序）。
- **每帧只画一只主体、居中、缩放一致**；洋红底或透明底皆可。

### 方式 ② 动图（视频/动画模型）
- 用图生视频模型（如 Runway / Kling / Pika / Luma / Sora）：把模板 A 的定妆图作为首帧，
  提示：`the creature performs <ACTION>, seamless loop, static camera, plain solid magenta background, no camera move`。
- 导出 **GIF 或 MP4**（1–2 秒，循环）。命名同上：`{animal}_{element}_{stage}_{action}.gif`。
- 注意：视频模型难保证干净透明底与完美循环，一致性也可能漂移；**若要最稳的透明循环，仍首选「方式 ① 独立帧序列」**。

---

## 回传规范（这样我能直接接入）

1. 首选 **独立帧 PNG 序列**：每个动作一组按序号命名的帧（例如 `_01`..`_30`），**每帧单只主体**。
2. 背景：优先透明；否则用纯 `#FF00FF` 洋红底（我来抠）。
3. 命名：`{animal}_{element}_{stage}_{action}_{NN}.png`，`NN` 为零填充帧序号；四阶段（egg/juvenile/mature/final）齐全更好。
   - state 映射：`idle→idle`、`attack→working`、`waiting→waiting`、`complete`/`hatch→complete`。
4. **⚠ 每帧只画一只主体**，不要把多只/多姿态排成一行（那会被当成多帧条）；帧数一致（如全 30 帧）最好。

## agentmon 侧接入

- 独立帧序列：`swift scripts/process-packs.swift <源目录（含 *_pack 子目录）> [帧高=160]`。
  按 `(species,stage,action)` 分组并按序号排序 → 逐帧抠洋红底 → 求全序列公共内容 bbox（保留帧间位移）→
  统一裁剪缩放 → 横排拼成紧凑透明条 + `manifest.json`。fps 按「一轮秒数」推导，帧越多越平滑而非越慢。
- **增量 + 自守卫**：预载已有 manifest，只覆盖处理成功的动作；某动作若被画成「一排多只」拼图（bbox 宽高比 > 1.7）
  会被跳过、不写文件、保留旧素材与旧条目 —— 之后按单只主体重出该动作、重跑脚本即可只更新那几个。
- App 与网页预览自动按 manifest 的帧数播放，并做交叉溶解补帧。
