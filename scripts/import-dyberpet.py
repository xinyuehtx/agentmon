#!/usr/bin/env python3
"""
把一个 DyberPet 角色目录（act_conf.json + action/<prefix>_<n>.png）转换成 agentmon 的
custom_pet 图集（manifest v2 + anim 透明条），供**本地**使用。

⚠️ 仅供本地使用：DyberPet 为 GPL-3.0，其内置角色可能含受版权保护的 IP。
本脚本只做格式转换（原创代码），**不**内置任何第三方素材；输出到
~/Library/Application Support/agentmon/custom_pet/（仓库与发布包之外，不会被提交/分发）。
App 会优先加载该目录（见 RasterPetStore.load）。删除该目录即恢复随包原创极光猫。

用法：python3 scripts/import-dyberpet.py <DyberPet 角色目录> [输出目录]
"""
import json
import os
import re
import sys

from PIL import Image

# 我方状态键 → DyberPet 动作名候选（按优先级取第一个存在的）
ACTION_MAP = {
    "idle": ["default", "stand", "sit", "idle"],
    "working": ["right_walk", "left_walk", "walk", "run", "default"],
    "waiting": ["sleep", "fall_asleep", "fallasleep", "default"],
    "complete": ["happy", "cheer", "excited", "default"],
    "evolve": ["happy", "cheer", "excited", "default"],
    "hungry": ["angry", "hungry", "sad", "default"],
    "jump": ["onfloor", "on_floor", "jump", "fall"],
    "skill": ["angry", "drag", "attack", "onfloor"],
}
FRAME_H = 160


def content_bbox(img):
    return img.split()[3].point(lambda a: 255 if a > 8 else 0).getbbox()


def union_bbox(a, b):
    if a is None:
        return b
    if b is None:
        return a
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def load_frames(role_dir, act):
    """act = act_conf 条目 {images, act_num}；按序号读 action/<images>_<n>.png
    （兼容任意零填充：stand_0.png / stand_00.png 都能匹配，数值排序）。"""
    prefix = act.get("images")
    action_dir = os.path.join(role_dir, "action")
    if not prefix or not os.path.isdir(action_dir):
        return []
    pat = re.compile(r"^" + re.escape(prefix) + r"_(\d+)\.png$")
    matched = []
    for f in os.listdir(action_dir):
        m = pat.match(f)
        if m:
            matched.append((int(m.group(1)), f))
    matched.sort()
    num = int(act.get("act_num", len(matched)) or len(matched))
    files = [f for _, f in matched][: max(1, num)] if matched else []
    return [Image.open(os.path.join(action_dir, f)).convert("RGBA") for f in files]


def build_strip(frames, frame_h):
    bbox = None
    for f in frames:
        bbox = union_bbox(bbox, content_bbox(f))
    if bbox is None:
        bbox = (0, 0, frames[0].width, frames[0].height)
    cropped = [f.crop(bbox) for f in frames]
    scale = frame_h / cropped[0].height
    fw = max(1, round(cropped[0].width * scale))
    resized = [c.resize((fw, frame_h), Image.LANCZOS) for c in cropped]
    strip = Image.new("RGBA", (fw * len(resized), frame_h), (0, 0, 0, 0))
    for i, im in enumerate(resized):
        strip.paste(im, (i * fw, 0))
    return strip, fw, len(resized)


def main():
    if len(sys.argv) < 2:
        print("用法：python3 scripts/import-dyberpet.py <DyberPet 角色目录> [输出目录]")
        sys.exit(1)
    role_dir = sys.argv[1]
    role = os.path.basename(role_dir.rstrip("/")) or "custom"
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser(
        "~/Library/Application Support/agentmon/custom_pet")

    with open(os.path.join(role_dir, "act_conf.json")) as f:
        act_conf = json.load(f)

    os.makedirs(os.path.join(out, "anim"), exist_ok=True)
    os.makedirs(os.path.join(out, "elements"), exist_ok=True)

    actions = {}
    idle_portrait = None
    for state, candidates in ACTION_MAP.items():
        act = next((act_conf[c] for c in candidates if c in act_conf), None)
        if act is None:
            continue
        frames = load_frames(role_dir, act)
        if not frames:
            continue
        strip, fw, n = build_strip(frames, FRAME_H)
        strip.save(os.path.join(out, "anim", f"{state}.png"))
        refresh = float(act.get("frame_refresh", 0.2) or 0.2)
        fps = max(1, round(1.0 / refresh)) if n > 1 else 1
        actions[state] = {"file": f"anim/{state}.png", "frames": n, "fw": fw, "fh": FRAME_H, "fps": fps}
        if state == "idle":
            idle_portrait = frames[0]
        print(f"{state}: {n} 帧, fw={fw} (源动作 {act.get('images')})")

    # 单角色作为唯一"元素"，避免收藏/挑选逻辑空转；立绘取 idle 首帧
    portrait_rel = f"elements/{role}.png"
    if idle_portrait is not None:
        bbox = content_bbox(idle_portrait) or (0, 0, idle_portrait.width, idle_portrait.height)
        idle_portrait.crop(bbox).save(os.path.join(out, portrait_rel))

    manifest = {
        "schemaVersion": 2,
        "character": role,
        "frameHeight": FRAME_H,
        "actions": actions,
        "elements": [{"id": role, "name": role, "portrait": portrait_rel, "tint": "#8AA0FF"}],
    }
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
    print(f"完成：{len(actions)} 动作 → {out}")
    print("重启 agentmon 即生效；删除该目录恢复随包原创极光猫。")


if __name__ == "__main__":
    main()
