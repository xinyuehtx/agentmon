#!/usr/bin/env python3
"""
处理「极光罗盘猫」素材包（aurora-compass-cat-animation-pack-v2）→ agentmon 光栅图集。

输入包结构：
  <pack>/frames/<NN-action>/<NN-action>-0K.png   8 动作 × 6 帧，512×512，米白底无 alpha
  <pack>/12-attribute-variants-v2.png            4×3 = 12 元素设定板（每格 512×512）

输出（assets/pets_raster/）：
  anim/<state>.png       每动作一张紧凑透明「条」（横排 frames 帧）
  elements/<id>.png      12 元素静态立绘（抠底透明）
  manifest.json          schemaVersion 2（actions + elements）

抠底：从四角 BFS 泛洪，颜色距米白 (254,249,243) < 阈值且与边界连通者置透明，
保留中心浅色猫体不被误伤。

用法：python3 scripts/process-aurora.py <解压后的 pack 目录> [frameH=160]

补帧（光流插帧，6 帧 → ~24 帧，播放更顺滑）需要 numpy / scipy / scikit-image：
  python3 -m venv /tmp/aurora-venv && /tmp/aurora-venv/bin/pip install scikit-image pillow
  /tmp/aurora-venv/bin/python scripts/process-aurora.py <pack 目录>
缺少这些库时自动回退为不补帧（原 6 帧）。
"""
import json
import os
import sys
from collections import deque

from PIL import Image

# 光流补帧（可选）：venv 装了 numpy/scipy/scikit-image 才启用，否则回退原帧。
try:
    import numpy as np
    from scipy.ndimage import map_coordinates
    from skimage.registration import optical_flow_tvl1

    HAVE_INTERP = True
except Exception:
    HAVE_INTERP = False

INTERP_STEPS = 4  # 每对关键帧之间插到 STEPS 个采样（含起点）→ 帧数约 ×STEPS
GEN_GHOST_LIMIT = 0.30  # 半透明占比中位数上限（与门禁 0.33 留余量）；超过则回退更少插帧

CREAM = (254, 249, 243)
BG_TOL = 30  # 与米白的每通道最大差
FRAME_H = 160

# 动作文件夹 → agentmon 状态键
ACTION_MAP = {
    "01-rest": "idle",
    "03-run": "working",
    "02-sleep": "waiting",
    "06-cheer": "complete",
    "08-happy": "evolve",
    "07-hungry": "hungry",
    "04-jump": "jump",
    "05-skill-attack": "skill",
}

# 一轮播放秒数 → 由帧数推 fps（帧越多越平滑而非越慢）
CYCLE = {"working": 0.9, "waiting": 1.1, "complete": 1.2, "evolve": 1.2,
         "hungry": 1.3, "jump": 0.8, "skill": 0.9, "idle": 1.4}

# 12 元素：board 从左到右、上到下（4 列 × 3 行）
ELEMENTS = [
    ("water", "水", "#4AA3FF"), ("grass", "草", "#64C46A"),
    ("fire", "火", "#FF7A3C"), ("wind", "风", "#6FE0C0"),
    ("electric", "电", "#F4C430"), ("ice", "冰", "#7FD4FF"),
    ("ghost", "幽灵", "#9B7EDE"), ("psychic", "超能", "#FF7EC8"),
    ("rock", "岩石", "#C9A24A"), ("light", "光", "#FFE6A0"),
    ("dark", "暗", "#5566CC"), ("rainbow", "彩虹", "#B98CFF"),
]


def is_bg(px):
    r, g, b, a = px
    if a == 0:
        return True
    return (abs(r - CREAM[0]) <= BG_TOL and abs(g - CREAM[1]) <= BG_TOL
            and abs(b - CREAM[2]) <= BG_TOL)


def remove_bg(img):
    """四角边界连通泛洪抠米白底；返回 RGBA。"""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = [False] * (w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = True
        if not is_bg(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        q.append((x + 1, y))
        q.append((x - 1, y))
        q.append((x, y + 1))
        q.append((x, y - 1))
    return img


def content_bbox(img):
    """非透明像素的 bbox（alpha>8）。"""
    alpha = img.split()[3]
    return alpha.point(lambda a: 255 if a > 8 else 0).getbbox()


def union_bbox(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


# --- 光流补帧 -------------------------------------------------------------

def _premult(a):
    o = a.copy()
    o[..., :3] *= a[..., 3:4]
    return o


def _unpremult(a):
    o = np.clip(a, 0, 1)
    al = np.clip(o[..., 3:4], 1e-4, 1)
    o[..., :3] = np.clip(o[..., :3] / al, 0, 1)
    return o


def _gray(a):  # 用 alpha 加权的亮度算光流，避免透明区干扰
    return (a[..., :3] * a[..., 3:4]).mean(-1)


def _warp(img, flow):
    h, w = img.shape[:2]
    r, c = np.meshgrid(np.arange(h), np.arange(w), indexing="ij")
    coords = np.array([r + flow[0], c + flow[1]])
    return np.stack(
        [map_coordinates(img[..., k], coords, order=1, mode="constant", cval=0) for k in range(4)], -1)


def _interp_pair(a, b, f_a, f_b, steps):
    """用预算好的双向光流在 A→B 之间插 steps 帧（含 A，不含 B）。"""
    ap, bp = _premult(a), _premult(b)
    out = []
    for k in range(steps):
        t = k / steps
        if t == 0:
            out.append(a.copy())
            continue
        at = _warp(ap, f_b * t)
        bt = _warp(bp, f_a * (1 - t))
        out.append(_unpremult((1 - t) * at + t * bt))
    return out


def interpolate(frames, steps, loop):
    """光流补帧到约 ×steps（每对帧统一 steps）；loop=True 首尾相接。"""
    if not HAVE_INTERP or steps <= 1 or len(frames) < 2:
        return frames
    arr = [np.asarray(f.convert("RGBA"), float) / 255.0 for f in frames]
    n = len(arr)
    out = []
    pairs = n if loop else n - 1
    for i in range(pairs):
        a, b = arr[i], arr[(i + 1) % n]
        f_a = np.array(optical_flow_tvl1(_gray(a), _gray(b), attachment=8, num_warp=5))  # warp B→A
        f_b = np.array(optical_flow_tvl1(_gray(b), _gray(a), attachment=8, num_warp=5))  # warp A→B
        out += _interp_pair(a, b, f_a, f_b, steps)
    if not loop:
        out.append(arr[-1])  # 一次性动作以最后一帧收尾
    return [Image.fromarray((np.clip(f, 0, 1) * 255).astype("uint8"), "RGBA") for f in out]


def _median_partial(frames):
    """帧序列「半透明像素占比」中位数——与 AssetIntegrityTests 门禁同口径的重影度量。"""
    fr = []
    for im in frames:
        a = np.asarray(im.convert("RGBA"))[..., 3].astype(int)
        c = (a > 16).sum()
        p = ((a > 40) & (a < 215)).sum()
        fr.append(p / max(1, c))
    return float(np.median(fr)) if fr else 0.0


def choose_interpolation(resized, loop):
    """自适应补帧：优先 4× 平滑；若重影度超阈值（如大位移跳跃）逐级回退 2×→原帧，保证清晰不糊。"""
    if not HAVE_INTERP:
        return resized, "no-skimage"
    for steps in (INTERP_STEPS, 2):
        cand = interpolate(resized, steps, loop)
        if _median_partial(cand) <= GEN_GHOST_LIMIT:
            return cand, f"{steps}x"
    return resized, "raw(大位移)"


def process_action(frames_dir, frame_h, loop):
    files = sorted(f for f in os.listdir(frames_dir) if f.lower().endswith(".png"))
    imgs = [remove_bg(Image.open(os.path.join(frames_dir, f))) for f in files]
    # 6 帧公共 bbox（保留帧间位移）
    bbox = None
    for im in imgs:
        bbox = union_bbox(bbox, content_bbox(im))
    if bbox is None:
        return None
    cropped = [im.crop(bbox) for im in imgs]
    cw, ch = cropped[0].size
    scale = frame_h / ch
    fw = max(1, round(cw * scale))
    resized = [im.resize((fw, frame_h), Image.LANCZOS) for im in cropped]
    resized, mode = choose_interpolation(resized, loop)  # 自适应光流补帧
    strip = Image.new("RGBA", (fw * len(resized), frame_h), (0, 0, 0, 0))
    for i, im in enumerate(resized):
        strip.paste(im, (i * fw, 0))
    return strip, fw, len(resized), mode


def slice_elements(board_path, out_dir):
    board = remove_bg(Image.open(board_path))
    w, h = board.size
    cw, ch = w // 4, h // 3  # 设定板为规整 4×3，每格同尺寸、角色位置一致
    out = {}
    for idx, (eid, _, _) in enumerate(ELEMENTS):
        col, row = idx % 4, idx // 4
        # 直接取规整方格（不按内容 bbox 裁剪，保证 12 张立绘尺寸/角色比例一致）
        cell = board.crop((col * cw, row * ch, (col + 1) * cw, (row + 1) * ch))
        path = os.path.join(out_dir, f"{eid}.png")
        cell.save(path)
        out[eid] = f"elements/{eid}.png"
    return out


def main():
    if len(sys.argv) < 2:
        print("用法：python3 scripts/process-aurora.py <pack 目录> [frameH]")
        sys.exit(1)
    pack = sys.argv[1]
    frame_h = int(sys.argv[2]) if len(sys.argv) > 2 else FRAME_H
    repo = os.getcwd()
    out = os.path.join(repo, "assets/pets_raster")

    # 清理旧内容
    if os.path.isdir(out):
        import shutil
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "anim"), exist_ok=True)
    os.makedirs(os.path.join(out, "elements"), exist_ok=True)

    actions = {}
    frames_root = os.path.join(pack, "frames")
    oneshot = {"complete", "evolve"}
    for folder, state in ACTION_MAP.items():
        d = os.path.join(frames_root, folder)
        if not os.path.isdir(d):
            print(f"跳过缺失动作 {folder}")
            continue
        res = process_action(d, frame_h, loop=state not in oneshot)
        if res is None:
            print(f"动作 {folder} 无内容，跳过")
            continue
        strip, fw, n, mode = res
        strip.save(os.path.join(out, "anim", f"{state}.png"))
        cycle = CYCLE.get(state, 1.4)
        fps = max(1, round(n / cycle))
        actions[state] = {"file": f"anim/{state}.png", "frames": n, "fw": fw, "fh": frame_h, "fps": fps}
        print(f"{folder} → {state}: {n} 帧, fw={fw}, 补帧={mode}")

    portraits = slice_elements(os.path.join(pack, "12-attribute-variants-v2.png"),
                               os.path.join(out, "elements"))
    elements = [{"id": eid, "name": name, "portrait": portraits[eid], "tint": tint}
                for (eid, name, tint) in ELEMENTS]

    manifest = {
        "schemaVersion": 2,
        "character": "aurora",
        "frameHeight": frame_h,
        "actions": actions,
        "elements": elements,
    }
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"完成：{len(actions)} 动作, {len(elements)} 元素 → {out}")


if __name__ == "__main__":
    main()
