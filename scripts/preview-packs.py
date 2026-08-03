#!/usr/bin/env python3
"""
生成「查看所有素材动效」的单页 HTML：扫描本地所有图集包（原创 + 本地导入），
把每个动作条切帧、每个元素立绘一并 base64 内联进 HTML，双击即可离线查看全部动画。

默认扫描：
  assets/pets_raster/packs/*      （随包原创图集，如草系罗盘猫 verdant）
  ~/Library/Application Support/agentmon/custom_pet          （当前生效的本地包）
  ~/Library/Application Support/agentmon/_sources/preview/*  （已导入预览的本地包）

用法：python3 scripts/preview-packs.py [额外包目录 ...]
输出：~/Library/Application Support/agentmon/pet-preview-all.html
（第三方素材仅在本地；本脚本为原创代码，不把任何第三方素材写入仓库。）
"""
import base64
import json
import os
import sys

APP = os.path.expanduser("~/Library/Application Support/agentmon")
ACTION_ORDER = ["idle", "working", "waiting", "complete", "evolve", "hungry", "jump", "skill"]


def b64(path):
    with open(path, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def load_pack(d):
    mf = os.path.join(d, "manifest.json")
    if not os.path.isfile(mf):
        return None
    m = json.load(open(mf))
    name = m.get("character", os.path.basename(d))

    def actions_of(actdict):
        out = {}
        for k, a in (actdict or {}).items():
            p = os.path.join(d, a["file"])
            if os.path.exists(p):
                out[k] = {"data": b64(p), "frames": a["frames"], "fps": a.get("fps", 8)}
        return out

    elements = []
    for e in (m.get("elements") or []):
        p = os.path.join(d, e.get("portrait", ""))
        if os.path.exists(p):
            elements.append({"name": e.get("name", e.get("id", "")), "data": b64(p),
                             "tint": e.get("tint", "#888")})

    # v3 多形态：每个形态展开为一个预览行
    if m.get("stages"):
        return [{"name": f"{name} · {s['stage']}", "dir": d,
                 "actions": actions_of(s.get("actions")), "elements": []}
                for s in m["stages"]]
    return [{"name": name, "dir": d, "actions": actions_of(m.get("actions")), "elements": elements}]


def main():
    packs_root = os.path.join(os.getcwd(), "assets/pets_raster/packs")
    dirs = [os.path.join(APP, "custom_pet")]
    if os.path.isdir(packs_root):
        dirs = [os.path.join(packs_root, x) for x in sorted(os.listdir(packs_root))
                if os.path.isdir(os.path.join(packs_root, x))] + dirs
    prev = os.path.join(APP, "_sources", "preview")
    if os.path.isdir(prev):
        dirs += [os.path.join(prev, x) for x in sorted(os.listdir(prev))
                 if os.path.isdir(os.path.join(prev, x))]
    dirs += sys.argv[1:]

    packs = []
    seen = set()
    for d in dirs:
        rp = os.path.realpath(d)
        if rp in seen:
            continue
        seen.add(rp)
        for p in (load_pack(d) or []):
            packs.append(p)
            print(f"pack: {p['name']:18} 动作={len(p['actions'])} 元素={len(p['elements'])}")

    data = json.dumps(packs, ensure_ascii=False)
    html = _TEMPLATE.replace("/*DATA*/", data)
    out = os.path.join(APP, "pet-preview-all.html")
    os.makedirs(APP, exist_ok=True)
    with open(out, "w") as f:
        f.write(html)
    print(f"完成：{len(packs)} 个包 → {out}")
    print("双击该文件即可在浏览器查看全部动效。")


_TEMPLATE = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"/>
<title>agentmon · 全部素材动效预览</title><style>
body{margin:0;background:#12141a;color:#e8eaed;font-family:-apple-system,system-ui,"PingFang SC",sans-serif}
h1{font-size:20px;text-align:center;padding:18px 0 4px}.muted{color:#9aa0aa;font-size:13px;text-align:center;margin:0 0 16px}
.pack{max-width:1100px;margin:0 auto 26px;padding:0 16px}
.pack h2{font-size:16px;border-bottom:1px solid #262b36;padding-bottom:6px}
.acts{display:flex;flex-wrap:wrap;gap:14px;margin:10px 0}
.act{text-align:center}.act canvas{background:radial-gradient(circle at 50% 45%,#1b2030,#0b0d12);border-radius:12px;display:block}
.act .n{font-size:11px;color:#9aa0aa;margin-top:3px}
.els{display:flex;flex-wrap:wrap;gap:8px}.el{width:66px;text-align:center}.el img{width:100%;background:#eef1f6;border-radius:8px;border:2px solid #333}
.el .n{font-size:11px;color:#c4c9d2}
footer{text-align:center;color:#6b7280;font-size:12px;margin:24px}
</style></head><body>
<h1>agentmon · 全部素材动效预览</h1>
<p class="muted">本地全部图集包（原创 + 本地导入）；第三方素材仅本地，不入仓库</p>
<div id="root"></div>
<footer>agentmon</footer>
<script>
var PACKS=/*DATA*/;
var ORDER=["idle","working","waiting","complete","evolve","hungry","jump","skill"];
var CN={idle:"发呆",working:"干活",waiting:"打盹",complete:"撒花",evolve:"开心",hungry:"饿了",jump:"跳跃",skill:"技能"};
var root=document.getElementById("root"), sprites=[];
PACKS.forEach(function(p){
  var box=document.createElement("div"); box.className="pack";
  var h=document.createElement("h2"); h.textContent=p.name+"（动作 "+Object.keys(p.actions).length+"）"; box.appendChild(h);
  var acts=document.createElement("div"); acts.className="acts";
  ORDER.filter(function(k){return p.actions[k];}).forEach(function(k){
    var a=p.actions[k], img=new Image(); img.src=a.data;
    var wrap=document.createElement("div"); wrap.className="act";
    var c=document.createElement("canvas"); c.width=96; c.height=96;
    var n=document.createElement("div"); n.className="n"; n.textContent=(CN[k]||k);
    wrap.appendChild(c); wrap.appendChild(n); acts.appendChild(wrap);
    sprites.push({img:img,ctx:c.getContext("2d"),frames:a.frames,fps:a.fps,w:c.width,h:c.height});
  });
  box.appendChild(acts);
  if(p.elements.length){
    var els=document.createElement("div"); els.className="els";
    p.elements.forEach(function(e){var d=document.createElement("div");d.className="el";
      var im=new Image();im.src=e.data;im.style.borderColor=e.tint;var nn=document.createElement("div");nn.className="n";nn.textContent=e.name;
      d.appendChild(im);d.appendChild(nn);els.appendChild(d);});
    box.appendChild(els);
  }
  root.appendChild(box);
});
function tick(ts){requestAnimationFrame(tick);sprites.forEach(function(s){
  if(!s.img.complete||!s.img.naturalWidth)return;
  var fw=s.img.naturalWidth/s.frames, fh=s.img.naturalHeight;
  var i=Math.floor(ts/1000*s.fps)%s.frames;
  var sc=Math.min(s.w/fw,s.h/fh)*0.92, w=fw*sc, h=fh*sc;
  s.ctx.clearRect(0,0,s.w,s.h);
  s.ctx.drawImage(s.img,i*fw,0,fw,fh,(s.w-w)/2,s.h-h-4,w,h);
});}
requestAnimationFrame(tick);
</script></body></html>"""


if __name__ == "__main__":
    main()
