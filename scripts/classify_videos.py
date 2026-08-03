#!/usr/bin/env python3
"""
把一批**时间戳命名**的原始视频（如 video-1785567100308.mp4）归类为
`<stage>/<action>.mp4` 布局，供 video_to_pack.py 处理。

背景：批量「原画 → 视频」生成工具通常**按形态分批、组内动作顺序固定**输出，
文件名只带时间戳。经验（本项目 verdant 验证）：
  - 按时间戳升序，每 <actions> 个为一个形态块，块顺序 = 形态顺序；
  - 组内动作顺序固定（本项目为 rest,cheer,attack,hungry,jump,sleep,run,happy）。
纯像素自动匹配不可靠（同角色多姿势），故本脚本采用
「生成核对图 + 人工确认 mapping.json + 应用」的半自动工作流。

用法：
  # 1) 生成核对图 + 默认 mapping.json（不改动文件）
  classify_videos.py --src mons/verdant/video/1 --stages egg,youth,mature,baby \
      --order rest,cheer,attack,hungry,jump,sleep,run,happy --out-review /tmp/review
  # 2) 人工看 /tmp/review/order_sheet.png 校对，必要时编辑 mapping.json
  # 3) 应用：把视频重命名/移动到 <dest>/<stage>/<action>.mp4
  classify_videos.py --src mons/verdant/video/1 --mapping /tmp/review/mapping.json --dest mons/verdant --apply

依赖：imageio imageio-ffmpeg pillow numpy（隔离 venv，见 video_to_pack.py 头部）。
"""
import argparse
import glob
import json
import os
import shutil

import numpy as np
from PIL import Image, ImageDraw
import imageio.v3 as iio

DEFAULT_ORDER = ["rest", "cheer", "attack", "hungry", "jump", "sleep", "run", "happy"]


def ts_sorted(src):
    vids = glob.glob(os.path.join(src, "*.mp4"))
    def key(p):
        import re
        m = re.search(r"(\d+)", os.path.basename(p))
        return int(m.group(1)) if m else p
    return sorted(vids, key=key)


def first_frame(v):
    return Image.fromarray(next(iter(iio.imiter(v)))).convert("RGB")


def build_mapping(vids, stages, order):
    """按「每 len(order) 个为一形态块」切分，组内套用固定动作顺序。"""
    per = len(order)
    assert len(vids) == len(stages) * per, \
        f"视频数 {len(vids)} ≠ 形态数 {len(stages)} × 动作数 {per}"
    mapping = {}
    for b, st in enumerate(stages):
        for p, v in enumerate(vids[b * per:(b + 1) * per]):
            mapping[f"{st}/{order[p]}"] = os.path.basename(v)
    return mapping


def order_sheet(vids, stages, order, out_png):
    """时间戳序首帧缩略图montage（按形态×动作网格），供人工核对分组与顺序。"""
    per = len(order)
    C = 150
    sheet = Image.new("RGB", (per * C, len(stages) * (C + 20) + 8), (22, 24, 30))
    d = ImageDraw.Draw(sheet)
    for b, st in enumerate(stages):
        y0 = b * (C + 20) + 4
        d.text((4, y0), st, fill=(255, 220, 120))
        for p, v in enumerate(vids[b * per:(b + 1) * per]):
            f = first_frame(v); f.thumbnail((C - 8, C - 8))
            sheet.paste(f, (p * C + 4, y0 + 14))
            d.text((p * C + 4, y0 + 14 + C - 26), f"{order[p]}", fill=(150, 200, 255))
    sheet.save(out_png)


def apply_mapping(src, mapping, dest, move):
    n = 0
    for rel, fname in mapping.items():
        srcp = os.path.join(src, fname)
        if not os.path.exists(srcp):
            print(f"  缺失 {fname}，跳过 {rel}"); continue
        dstp = os.path.join(dest, rel + ".mp4")
        os.makedirs(os.path.dirname(dstp), exist_ok=True)
        (shutil.move if move else shutil.copy2)(srcp, dstp)
        n += 1
    print(f"{'移动' if move else '复制'} {n} 个视频 → {dest}/<stage>/<action>.mp4")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="原始视频目录（时间戳命名）")
    ap.add_argument("--stages", default="egg,youth,mature,baby", help="形态顺序（逗号分隔）")
    ap.add_argument("--order", default=",".join(DEFAULT_ORDER), help="组内动作顺序（逗号分隔）")
    ap.add_argument("--out-review", default="/tmp/agentmon-review", help="核对图/mapping 输出目录")
    ap.add_argument("--mapping", default=None, help="应用阶段：读取此 mapping.json")
    ap.add_argument("--dest", default=None, help="应用阶段：目标 mon 目录")
    ap.add_argument("--apply", action="store_true", help="执行重命名/移动（否则只生成核对图）")
    ap.add_argument("--copy", action="store_true", help="应用时复制而非移动")
    args = ap.parse_args()

    if args.apply:
        assert args.mapping and args.dest, "--apply 需 --mapping 与 --dest"
        mapping = json.load(open(args.mapping))
        apply_mapping(args.src, mapping, args.dest, move=not args.copy)
        return

    vids = ts_sorted(args.src)
    stages = args.stages.split(","); order = args.order.split(",")
    os.makedirs(args.out_review, exist_ok=True)
    mapping = build_mapping(vids, stages, order)
    order_sheet(vids, stages, order, os.path.join(args.out_review, "order_sheet.png"))
    json.dump(mapping, open(os.path.join(args.out_review, "mapping.json"), "w"),
              ensure_ascii=False, indent=2)
    print(f"生成核对图 {args.out_review}/order_sheet.png 与 mapping.json")
    print("请核对分组/顺序，必要时编辑 mapping.json，然后带 --apply --mapping --dest 应用。")


if __name__ == "__main__":
    main()
