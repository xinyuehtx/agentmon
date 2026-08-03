---
name: pet-material-pipeline
description: >
  把原创素材（每动作一段视频，或分形态的视频/原画）做成 agentmon 桌宠图集包：
  归类命名 → 去背景/去角标字母 → 生成透明动作条 + manifest → 预览。
  当需要「新增一只桌宠 / 给某 mon 加素材 / 把视频转成桌宠动作 / 重新切图」时使用。
---

# 桌宠素材流水线（视频/原画 → 图集包）

把原创素材沉淀为 agentmon 可用的透明逐帧动作条 + manifest。全流程脚本化、可复现。

> **仅限原创或明确授权素材**。第三方 IP/GPL 素材不入仓库、不随发布分发（见 README「版权与素材合法性」），
> 只能走本地 `~/Library/Application Support/agentmon/custom_pet/`。

## 0. 环境（隔离 venv，一次性）

```bash
python3 -m venv /tmp/agentmon-venv
/tmp/agentmon-venv/bin/pip install imageio imageio-ffmpeg pillow numpy scipy "rembg[cpu]"
```
之后所有脚本用 `/tmp/agentmon-venv/bin/python` 运行。rembg 首次调用会下载 u2net 模型（~176MB，缓存于 `~/.u2net`）。

## 1. 归类命名（若素材是时间戳命名的原始视频）

批量「原画→视频」工具常**按形态分批、组内动作顺序固定**输出，文件名只带时间戳。
`classify_videos.py` 采用「生成核对图 → 人工确认 mapping → 应用」半自动流程（纯像素自动匹配不可靠：同角色多姿势区分度低）。

```bash
# 生成核对图 + 默认 mapping.json（不改文件）
/tmp/agentmon-venv/bin/python scripts/classify_videos.py \
  --src mons/<mon>/video/1 \
  --stages egg,youth,mature,baby \
  --order rest,cheer,attack,hungry,jump,sleep,run,happy \
  --out-review /tmp/review
# 打开 /tmp/review/order_sheet.png 核对分组与组内顺序；必要时编辑 mapping.json
# 应用：重命名/移动到 <mon>/<stage>/<action>.mp4
/tmp/agentmon-venv/bin/python scripts/classify_videos.py \
  --src mons/<mon>/video/1 --mapping /tmp/review/mapping.json --dest mons/<mon> --apply
```

**经验（verdant 实证）**：
- 形态时间戳块顺序需人工确认（不一定是成长序）；verdant 为 `egg, youth, mature, baby`。
- 组内动作固定顺序：`rest, cheer, attack, hungry, jump, sleep, run, happy`（睡姿恒在第 6 位=索引5，可作校验锚点）。
- 判姿势技巧：`sleep`=蜷缩+Z、`run`=侧向奔跑、`jump`=腾空、`hungry`=委屈、`happy`=举手；成熟态按体型分两组（双足 vs 四足）更易读；`attack`/`cheer` 最难分，用最清晰的形态（有能量气场=attack）定序。

## 2. 视频 → 图集包

`video_to_pack.py`：抽帧 → **去左上角残留字母** → 抠背景 → 并集 bbox 裁剪 → 缩放 → 横排透明条 → manifest。

```bash
# 多形态 mon（含 egg/youth/... 子目录，各含 <action>.mp4）→ manifest v3（stages）
/tmp/agentmon-venv/bin/python scripts/video_to_pack.py \
  --mon-dir mons/verdant --out assets/pets_raster/packs/verdant \
  --element grass --frames 24 --bg rembg

# 单形态（一个目录里的 <action>.mp4）→ manifest v2
/tmp/agentmon-venv/bin/python scripts/video_to_pack.py \
  --stage-dir mons/foo/base --out assets/pets_raster/packs/foo --name foo
```

**参数经验**：
- `--bg rembg`（默认）语义抠图：边缘干净、**能去角色内部/腿间的闭合背景**；`--bg corner` 纯色底泛洪更快（但不去闭合镂空、且会吃掉与边界相连的白色特效）；`--bg none` 已透明素材。
- `--tl-w 0.15 --tl-h 0.13`：左上角字母抹除区（宽/高占比）。角色居中时安全；若角色偏左调小。
- `--frames 24`：视频帧多（本项目 73），24 帧循环足够顺滑，**无需补帧**。
- `--frame-h 160`：动作条帧高。
- `--dropout-frac 0.3`：抠图门禁阈值（见下）。
- 动作名映射（原素材名→状态键）：`rest→idle, run→working, sleep→waiting, cheer→complete, happy→evolve, hungry→hungry, jump→jump, attack→skill`（见脚本 `ACTION_ALIASES`）。

**逐帧混合抠图 + 抠图后门禁（重要，解决两类真实问题）**：
- 问题①「全屏亮白特效帧被抠没主体」：rembg 会把被绿/白能量爆发笼罩的角色误当背景抠掉 → 该帧近空 → 播放闪烁/掉帧。
- 问题②「闭合背景没抠净」：四角泛洪抠不掉被主体包围的白色空洞（腿间/尾环内）。
- **方案（脚本已内置，默认生效）**：**逐帧混合**——默认 rembg（干净、去闭合背景）；某帧被 rembg 抠得「实心像素(alpha>16)面积 < 中位数 × dropout_frac」→ 该帧回退四角泛洪保主体；若两法都救不回（纯白闪帧，白效果与白底无法区分）→ 用**最近的好帧顶替**（保帧数、消闪烁）。
- **抠图门禁**：`opaque_area` 用 alpha>16「实心」口径（与 Swift 门禁 `AssetIntegrityTests.testPackFramesNoDropout` 同口径），任一帧实心面积 < 中位数×0.3 会告警并触发上述回退/顶替。
- 排查技巧：把某动作条各帧贴到**品红底**上看——真·残留白背景会是白色孤岛；奶白蛋壳/白肚毛是主体（品红只在轮廓外）。别用「近白+闭合」自动判残留背景，会把白色主体误报。

**CI 门禁**：`tests/integration/AssetIntegrityTests.swift`
- `testPackFramesNoDropout`：扫描 `assets/pets_raster/packs/*/manifest.json`（v2/v3），任一动作条有帧实心面积 < 中位数×25% 即失败（抠图掉帧）。
- 另有结构/几何/立绘尺寸一致/帧非空/补帧重影等门禁。新素材入库前 `swift test` 必过。

## 3. 预览核对

```bash
/tmp/agentmon-venv/bin/python scripts/preview-packs.py     # 扫描 assets/pets_raster/** + custom_pet + _sources/preview
open "~/Library/Application Support/agentmon/pet-preview-all.html"   # 多形态每形态一行，逐动作动效
```
逐形态逐动作核对：左上角字母是否清除、白底是否透明、边缘是否干净、循环是否顺滑。

## 4. 落地

- **本地试跑**：拷到 `~/Library/Application Support/agentmon/custom_pet/`（App 优先加载；删除即恢复原创）。
- **入包**：原创素材可放 `assets/pets_raster/packs/<mon>/` 并提交。
- manifest：v2=单形态（`actions`），v3=多形态（`stages:[{stage,actions}]`）；`RasterLibrary` 向后兼容解码。

## 相关文件
- `scripts/classify_videos.py` · `scripts/video_to_pack.py` · `scripts/preview-packs.py`
- `Sources/Core/RasterLibrary.swift`（manifest v2/v3 结构）
