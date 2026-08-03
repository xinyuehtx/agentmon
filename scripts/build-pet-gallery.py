#!/usr/bin/env python3
"""
生成桌宠资源展示页（GitHub Pages）：把某个图集包的「每形态 × 每动作」渲染成
带透明通道的动图（animated WebP），并产出一页 docs/pets.html 画廊。

用法：
  /tmp/agentmon-venv/bin/python scripts/build-pet-gallery.py [包名=verdant] [帧高=120]

输入：assets/pets_raster/packs/<包名>/manifest.json（v3 多形态 / v2 单形态均可）
输出：docs/pets/<形态>-<动作>.webp  +  docs/pets.html
"""
import json
import os
import sys

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STAGE_ZH = {
    "egg": ("蛋", "Lv0"), "baby": ("幼体", "Lv1"),
    "youth": ("少年", "Lv2"), "mature": ("成熟", "Lv3"),
    # 兼容旧命名
    "juvenile": ("幼年", ""), "final": ("成年", ""),
}
ACTION_ZH = {
    "idle": "发呆", "working": "干活", "waiting": "等待", "complete": "完成",
    "evolve": "进化", "hungry": "饿了", "jump": "跳跃", "skill": "技能",
}
ACTION_ORDER = ["idle", "working", "waiting", "complete", "evolve", "hungry", "jump", "skill"]


def render_webp(pack_dir, action, out_path, height):
    """动作条 → 透明动图（隔帧减半 + 缩放），保持原播放速度。返回展示宽度(px)。"""
    strip = Image.open(os.path.join(pack_dir, action["file"])).convert("RGBA")
    n = action["frames"]
    fw = strip.width // n
    idx = list(range(0, n, 2)) or [0]  # 隔帧减半，动图更小
    frames = []
    for i in idx:
        f = strip.crop((i * fw, 0, (i + 1) * fw, strip.height))
        w = max(1, int(f.width * height / f.height))
        frames.append(f.resize((w, height), Image.LANCZOS))
    dur = max(1, int(1000 / action.get("fps", 12) * 2))  # 帧减半→时长翻倍，速度不变
    frames[0].save(out_path, save_all=True, append_images=frames[1:],
                   duration=dur, loop=0, format="WEBP", quality=80, method=4)
    return frames[0].width


def stages_of(m):
    """统一成 [(stage_id, actions_dict)]：v3 用 stages，v2 用顶层 actions（单形态）。"""
    if m.get("stages"):
        return [(s["stage"], s["actions"]) for s in m["stages"]]
    return [("", m.get("actions", {}))]


def main():
    pack = sys.argv[1] if len(sys.argv) > 1 else "verdant"
    height = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    pack_dir = os.path.join(REPO, "assets/pets_raster/packs", pack)
    m = json.load(open(os.path.join(pack_dir, "manifest.json")))
    out_dir = os.path.join(REPO, "docs/pets")
    os.makedirs(out_dir, exist_ok=True)

    sections = []
    total = 0
    for sid, actions in stages_of(m):
        cards = []
        ordered = [k for k in ACTION_ORDER if k in actions] + \
                  [k for k in actions if k not in ACTION_ORDER]
        for act in ordered:
            base = f"{sid or 'main'}-{act}"
            rel = f"pets/{base}.webp"
            w = render_webp(pack_dir, actions[act], os.path.join(out_dir, f"{base}.webp"), height)
            total += 1
            label = ACTION_ZH.get(act, act)
            cards.append(
                f'      <figure class="card"><div class="stage-img" style="height:{height}px">'
                f'<img src="{rel}" width="{w}" height="{height}" alt="{label}" loading="lazy"/></div>'
                f'<figcaption>{label}</figcaption></figure>')
        zh, lv = STAGE_ZH.get(sid, (sid or "形态", ""))
        title = f"{zh} <span class=\"lv\">{lv}</span>" if lv else zh
        sections.append(
            f'  <section class="stage">\n    <h2>{title}</h2>\n    <div class="grid">\n'
            + "\n".join(cards) + "\n    </div>\n  </section>")

    char = m.get("character", pack)
    elem = m.get("element", "")
    elem_txt = f"· {elem} 系" if elem else ""
    html = _TEMPLATE.replace("/*CHAR*/", char).replace("/*ELEM*/", elem_txt) \
                    .replace("/*SECTIONS*/", "\n".join(sections)) \
                    .replace("/*NSTAGE*/", str(len(sections))) \
                    .replace("/*NANIM*/", str(total))
    out_html = os.path.join(REPO, "docs/pets.html")
    with open(out_html, "w") as f:
        f.write(html)
    print(f"完成：{pack} → {total} 个动图 + docs/pets.html（{len(sections)} 形态）")


_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>agentmon 桌宠图鉴 · /*CHAR*/</title>
<style>
  :root { --bg:#f2f8f4; --card:#fff; --fg:#20342a; --muted:#5b7266; --line:#dcebe1; --accent:#3f9d6a; }
  * { box-sizing: border-box; }
  body { margin:0; font-family:-apple-system,"SF Pro Text","PingFang SC",system-ui,sans-serif;
    background:linear-gradient(180deg,#eef7f0,#e3f1e8 60%,#dbeee2); color:var(--fg); line-height:1.6; }
  header { text-align:center; padding:56px 20px 12px; }
  header h1 { margin:0 0 8px; font-size:30px; }
  header p { margin:0; color:var(--muted); font-size:16px; }
  header .meta { margin-top:14px; font-size:13px; color:var(--muted); }
  header a { color:var(--accent); text-decoration:none; }
  main { max-width:1080px; margin:0 auto; padding:20px 20px 60px; }
  .stage { margin:34px 0 8px; }
  .stage h2 { font-size:22px; margin:0 0 16px; padding-left:12px; border-left:4px solid var(--accent); }
  .stage h2 .lv { color:var(--accent); font-size:15px; font-weight:600; margin-left:6px; }
  .grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(150px,1fr)); gap:14px; }
  .card { margin:0; background:var(--card); border:1px solid var(--line); border-radius:16px;
    padding:14px 8px 10px; text-align:center; box-shadow:0 1px 3px rgba(30,80,50,.05);
    transition:transform .15s ease, box-shadow .15s ease; }
  .card:hover { transform:translateY(-3px); box-shadow:0 6px 18px rgba(30,80,50,.12); }
  .stage-img { display:flex; align-items:center; justify-content:center; }
  .stage-img img { image-rendering:auto; max-width:100%; height:100%; object-fit:contain; }
  figcaption { margin-top:8px; font-size:14px; color:var(--muted); }
  footer { text-align:center; color:var(--muted); font-size:13px; padding:8px 20px 56px; }
</style>
</head>
<body>
<header>
  <h1>🐱 agentmon 桌宠图鉴</h1>
  <p>原创角色「/*CHAR*/」/*ELEM*/ · /*NSTAGE*/ 形态进化 · /*NANIM*/ 段动作动画</p>
  <p class="meta">随工作状态积累能量、升级即进化：蛋 → 幼体 → 少年 → 成熟 &nbsp;·&nbsp; <a href="./index.html">← 返回首页</a></p>
</header>
<main>
/*SECTIONS*/
</main>
<footer>全部为作者原创素材（AI 生成视频经 <code>scripts/video_to_pack.py</code> 制作），非任何既有 IP。<br/>
素材依 <a href="https://github.com/xinyuehtx/agentmon/blob/main/LICENSE-ASSETS.md">CC BY 4.0</a> 授权：可自由使用/修改/再分发，需署名「agentmon（github.com/xinyuehtx/agentmon）」。&nbsp;·&nbsp; <a href="./index.html">返回首页</a></footer>
</body>
</html>
"""


if __name__ == "__main__":
    main()
