#!/usr/bin/env python3
"""
视频 → agentmon 桌宠图集包（透明动作条 + manifest）。

适用于自制 / AI 生成的**原创**视频（每个动作一段短片）。处理流程：
  抽帧 → 去左上角残留字母（角标区填背景） → 抠背景（rembg 语义 / 四角泛洪） →
  跨帧并集 bbox 裁剪 → 缩放到 frameH → 横排透明条 → manifest。

两种输入：
  --stage-dir DIR   一个形态目录（内含 <action>.mp4）→ 单形态 manifest v2
  --mon-dir DIR     一个 mon 目录（内含多个形态子目录，各含 <action>.mp4）→ 多形态 manifest v3

依赖（隔离 venv）：
  python3 -m venv /tmp/agentmon-venv
  /tmp/agentmon-venv/bin/pip install imageio imageio-ffmpeg pillow numpy "rembg[cpu]"
  /tmp/agentmon-venv/bin/python scripts/video_to_pack.py --mon-dir mons/verdant --out assets/pets_raster/packs/verdant

用法示例：
  video_to_pack.py --mon-dir mons/verdant --element grass --frames 24 --bg rembg
  video_to_pack.py --stage-dir mons/foo/base --name foo --bg corner
"""
import argparse
import json
import os
from collections import deque

import numpy as np
from PIL import Image
import imageio.v3 as iio

ACTIONS = ["idle", "working", "waiting", "complete", "evolve", "hungry", "jump", "skill"]
# 视频动作名（原素材命名）→ agentmon 状态键
ACTION_ALIASES = {
    "rest": "idle", "run": "working", "sleep": "waiting", "cheer": "complete",
    "happy": "evolve", "hungry": "hungry", "jump": "jump", "attack": "skill",
    # 直接同名也接受
    "idle": "idle", "working": "working", "waiting": "waiting", "complete": "complete",
    "evolve": "evolve", "skill": "skill",
}
CYCLE = {"working": 0.9, "waiting": 1.1, "complete": 1.2, "evolve": 1.2, "hungry": 1.3,
         "jump": 0.8, "skill": 0.9, "idle": 1.4}
FRAME_H = 160

_REMBG = None


def rembg_session():
    global _REMBG
    if _REMBG is None:
        from rembg import new_session
        _REMBG = new_session("u2net")
    return _REMBG


def blank_topleft(im, wfrac, hfrac):
    """把左上角矩形填成白（去除生成残留的 F1/F5 等角标字母）。角色居中时该区恒为背景。"""
    a = np.asarray(im.convert("RGB")).copy()
    h, w = a.shape[:2]
    a[: int(h * hfrac), : int(w * wfrac)] = (255, 255, 255)
    return Image.fromarray(a)


def remove_bg_corner(img, tol=26):
    """四角边界连通泛洪抠底（纯色/近纯色背景，快）。不处理角色内部镂空。"""
    im = img.convert("RGBA")
    w, h = im.size
    px = im.load()
    corners = [px[1, 1], px[w - 2, 1], px[1, h - 2], px[w - 2, h - 2]]
    bg = tuple(int(np.median([c[k] for c in corners])) for k in range(3))
    seen = bytearray(w * h)
    q = deque([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
              + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y * w + x]:
            continue
        seen[y * w + x] = 1
        p = px[x, y]
        if abs(p[0] - bg[0]) <= tol and abs(p[1] - bg[1]) <= tol and abs(p[2] - bg[2]) <= tol:
            px[x, y] = (0, 0, 0, 0)
            q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return im


def remove_bg(img, mode):
    if mode == "none":
        return img.convert("RGBA")
    if mode == "corner":
        return remove_bg_corner(img)
    from rembg import remove
    return remove(img.convert("RGBA"), session=rembg_session()).convert("RGBA")


def content_bbox(im):
    return im.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox()


def union_bbox(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def sample_frames(path, n):
    frames = [Image.fromarray(f) for f in iio.imiter(path)]
    if not frames:
        return []
    if len(frames) <= n:
        return frames
    idx = [round(i * (len(frames) - 1) / (n - 1)) for i in range(n)]
    return [frames[i] for i in idx]


def opaque_area(im):
    # 只算“实心”像素(alpha>16)，与 Swift 门禁 AssetIntegrityTests 同口径：
    # 避免把大片半透明淡影/柔边残留误判为“有内容”，从而漏掉视觉上近空的淡出帧。
    return int((np.asarray(im.split()[3]) > 16).sum())


def detect_dropout(cut, frac=0.3):
    """抠图后检测门禁①：某些帧不透明面积骤降到中位数 frac 以下 →
    多半是抠图过狠把主体（全屏特效帧里的角色）也抠掉了。返回骤降帧索引 + 中位数。"""
    areas = [opaque_area(im) for im in cut]
    if not areas:
        return [], 0.0
    med = float(np.median(areas))
    if med <= 0:
        return list(range(len(areas))), med
    return [i for i, a in enumerate(areas) if a < frac * med], med


def mat_frames(raw, args):
    """逐帧混合抠图：默认 rembg（语义、边缘干净、能去闭合背景）；
    若某帧被 rembg 抠得主体丢失（面积骤降），该帧回退四角泛洪（白底安全、保全屏特效主体）。"""
    prepped = [blank_topleft(f, args.tl_w, args.tl_h) for f in raw]
    if args.bg != "rembg":
        return [remove_bg(f, args.bg) for f in prepped], 0
    cut = [remove_bg(f, "rembg") for f in prepped]
    areas = [opaque_area(c) for c in cut]
    med = float(np.median(areas)) if areas else 0.0
    fb = 0
    if med > 0:
        for i, a in enumerate(areas):
            if a < args.dropout_frac * med:  # rembg 把这帧主体抠没了 → 换四角泛洪保主体
                cut[i] = remove_bg(prepped[i], "corner")
                fb += 1
        # 兜底：全屏亮白特效帧两法都救不回（白效果与白底难分）→ 用最近的“好帧”顶替（保帧数、消闪烁）
        areas = [opaque_area(c) for c in cut]
        good = [i for i, a in enumerate(areas) if a >= args.dropout_frac * med]
        held = 0
        if good:
            for i, a in enumerate(areas):
                if a < args.dropout_frac * med:
                    j = min(good, key=lambda g: abs(g - i))  # 最近的好帧
                    cut[i] = cut[j].copy()
                    held += 1
        if held:
            print(f"    ↳ {held} 帧全屏特效两法均救不回，已用最近好帧顶替")
    return cut, fb


def build_action(video, args):
    """一段视频 → (透明条 PIL, fw, frames)。逐帧混合抠图 + 抠图后双门禁（掉帧/闭合背景）。"""
    raw = sample_frames(video, args.frames)
    if not raw:
        return None
    cut, fb = mat_frames(raw, args)
    if fb:
        print(f"    ↳ {fb} 帧 rembg 抠没主体，已回退四角泛洪")
    # 抠图后门禁：主体骤降（rembg 把全屏特效帧的角色抠没了）。已逐帧回退，此处兜底报告。
    bad, _ = detect_dropout(cut, args.dropout_frac)
    if bad:
        print(f"    ⚠ 门禁: {len(bad)} 帧不透明面积仍骤降（疑掉帧/抠图过狠）idx={bad[:8]}")
    bbox = None
    for im in cut:
        bbox = union_bbox(bbox, content_bbox(im))
    if bbox is None:
        return None
    cropped = [im.crop(bbox) for im in cut]
    scale = args.frame_h / cropped[0].height
    fw = max(1, round(cropped[0].width * scale))
    resized = [c.resize((fw, args.frame_h), Image.LANCZOS) for c in cropped]
    strip = Image.new("RGBA", (fw * len(resized), args.frame_h), (0, 0, 0, 0))
    for i, im in enumerate(resized):
        strip.paste(im, (i * fw, 0))
    return strip, fw, len(resized)


def action_key(name):
    return ACTION_ALIASES.get(name.lower())


def process_stage(stage_dir, out_dir, rel_prefix, args):
    """处理一个形态目录里的 <action>.mp4 → out_dir/anim/<key>.png，返回 actions dict。"""
    os.makedirs(os.path.join(out_dir, "anim"), exist_ok=True)
    actions = {}
    for f in sorted(os.listdir(stage_dir)):
        if not f.lower().endswith((".mp4", ".mov", ".webm")):
            continue
        key = action_key(os.path.splitext(f)[0])
        if key is None:
            print(f"  跳过未知动作 {f}")
            continue
        res = build_action(os.path.join(stage_dir, f), args)
        if res is None:
            print(f"  {f}: 无帧，跳过")
            continue
        strip, fw, n = res
        strip.save(os.path.join(out_dir, "anim", f"{key}.png"))
        fps = max(1, round(n / CYCLE.get(key, 1.4)))
        actions[key] = {"file": f"{rel_prefix}anim/{key}.png", "frames": n, "fw": fw, "fh": args.frame_h, "fps": fps}
        print(f"  {f} → {key}: {n} 帧 fw={fw}")
    return actions


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--stage-dir", help="单形态目录（含 <action>.mp4）")
    g.add_argument("--mon-dir", help="mon 目录（含多个形态子目录）")
    ap.add_argument("--out", required=True, help="输出包目录")
    ap.add_argument("--name", default=None, help="角色名（默认取目录名）")
    ap.add_argument("--element", default=None, help="属性（如 grass）")
    ap.add_argument("--frames", type=int, default=24)
    ap.add_argument("--frame-h", type=int, default=FRAME_H)
    ap.add_argument("--bg", default="rembg", choices=["rembg", "corner", "none"])
    ap.add_argument("--tl-w", type=float, default=0.15, help="左上角字母区宽度占比")
    ap.add_argument("--tl-h", type=float, default=0.13, help="左上角字母区高度占比")
    ap.add_argument("--dropout-frac", type=float, default=0.3,
                    help="掉帧门禁阈值：帧不透明面积 < 中位数×此值 → 判为主体被抠没，回退四角泛洪")
    ap.add_argument("--stages", default=None,
                    help="逗号分隔的形态顺序（默认 egg,baby,youth,mature 中存在者）")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)

    if args.stage_dir:
        name = args.name or os.path.basename(os.path.abspath(args.stage_dir))
        actions = process_stage(args.stage_dir, args.out, "", args)
        manifest = {"schemaVersion": 2, "character": name, "frameHeight": args.frame_h,
                    "actions": actions, "elements": []}
    else:
        name = args.name or os.path.basename(os.path.abspath(args.mon_dir))
        default_order = ["egg", "baby", "youth", "mature"]
        present = [d for d in os.listdir(args.mon_dir) if os.path.isdir(os.path.join(args.mon_dir, d))
                   and any(x.lower().endswith(".mp4") for x in os.listdir(os.path.join(args.mon_dir, d)))]
        order = (args.stages.split(",") if args.stages
                 else [s for s in default_order if s in present] + [s for s in present if s not in default_order])
        stages = []
        for st in order:
            sd = os.path.join(args.mon_dir, st)
            if not os.path.isdir(sd):
                continue
            print(f"[{st}]")
            acts = process_stage(sd, os.path.join(args.out, st), f"{st}/", args)
            if acts:
                stages.append({"stage": st, "actions": acts})
        manifest = {"schemaVersion": 3, "character": name, "frameHeight": args.frame_h,
                    "stages": stages, "elements": []}
    if args.element:
        manifest["element"] = args.element

    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
    nstage = len(manifest.get("stages", [])) or 1
    print(f"\n完成：{name} · {nstage} 形态 → {args.out}/manifest.json  (bg={args.bg})")


if __name__ == "__main__":
    main()
