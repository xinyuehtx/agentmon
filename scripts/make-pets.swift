#!/usr/bin/env swift
//
// 生成 agentmon 宠物精灵 + 动画数据（离屏纯数据 + PNG 预览，无需 GUI）。
// 原创三系精灵（草/火/水），复古像素怪物「画风」，非任何既有 IP。
// 用图元 + 自动描边 + 上光/下影绘制基础像素图，再把 4 类动作烘焙成显式帧序列。
//
// 用法（仓库根目录）：  swift scripts/make-pets.swift
// 产出：assets/pets.json  ·  docs/pet-preview.html  ·  docs/pet-sprites.png（肉眼校验用）
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 24
let H = 24
typealias Grid = [[Character]]

func blank() -> Grid { Array(repeating: Array(repeating: Character("."), count: W), count: H) }
func plot(_ g: inout Grid, _ x: Int, _ y: Int, _ c: Character) {
    if y >= 0, y < H, x >= 0, x < W { g[y][x] = c }
}
func fillEllipse(_ g: inout Grid, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ c: Character) {
    let y0 = max(0, Int(cy - ry)), y1 = min(H - 1, Int(cy + ry + 1))
    let x0 = max(0, Int(cx - rx)), x1 = min(W - 1, Int(cx + rx + 1))
    guard y0 <= y1, x0 <= x1 else { return }
    for y in y0...y1 {
        for x in x0...x1 {
            let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
            if dx * dx + dy * dy <= 1.0 { g[y][x] = c }
        }
    }
}
func rows(_ g: Grid) -> [String] { g.map { String($0) } }

func isSolid(_ ch: Character) -> Bool { ch != "." && ch != "K" }

/// 在整个不透明轮廓外描一圈 K（深色描边）。
func outline(_ g: inout Grid) {
    let src = g
    for y in 0..<H {
        for x in 0..<W where src[y][x] == "." {
            var near = false
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
                let nx = x + dx, ny = y + dy
                if nx >= 0, nx < W, ny >= 0, ny < H, isSolid(src[ny][nx]) { near = true; break }
            }
            if near { g[y][x] = "K" }
        }
    }
}

func shift(_ g: Grid, _ dx: Int, _ dy: Int) -> Grid {
    var out = blank()
    for y in 0..<H {
        for x in 0..<W where g[y][x] != "." { plot(&out, x + dx, y + dy, g[y][x]) }
    }
    return out
}
// 纵向挤压/拉伸（squash & stretch），围绕底部基线
func squash(_ g: Grid, _ dy: Int) -> Grid {
    // dy>0 压扁（下移顶部），dy<0 拉高。近似：仅整体轻移，避免重采样失真
    return shift(g, 0, dy)
}
func overlay(_ g: Grid, _ cells: [(Int, Int, Character)]) -> Grid {
    var out = g
    for (x, y, c) in cells { plot(&out, x, y, c) }
    return out
}
func closeEyes(_ g: Grid) -> Grid {
    var out = g
    for y in 0..<H {
        for x in 0..<W where out[y][x] == "E" || out[y][x] == "e" { out[y][x] = "B" }
    }
    // 画一条闭眼横线（用描边色）
    return out
}

// MARK: - 物种

struct Species {
    let id: String
    let name: String
    let element: String
    let palette: [String: String]
    let draw: (Int) -> Grid  // stageScale: 0 juvenile,1 mature,2 final
}

let confetti: [String: String] = ["p": "#ff6fb5", "y": "#ffd23c", "c": "#5fe0ff", "n": "#7be07b"]

// 通用色位：K 描边 / S 暗 / A 中 / B 亮 / H 高光 / W 腹白 / E 眼 / e 眼神光 / C 元素1 / D 元素2
func pal(_ base: [String: String]) -> [String: String] { base.merging(confetti) { a, _ in a } }

// 通用：给身体加上光下影 + 眼睛 + 腮红/嘴
func shadeBody(_ g: inout Grid, cx: Double, cy: Double, rx: Double, ry: Double) {
    // 高光（上方偏小的亮椭圆）
    fillEllipse(&g, cx - rx * 0.15, cy - ry * 0.35, rx * 0.62, ry * 0.5, "H")
    // 中间调
    fillEllipse(&g, cx, cy, rx * 0.9, ry * 0.55, "B")
    // 下影
    fillEllipse(&g, cx, cy + ry * 0.55, rx * 0.8, ry * 0.4, "S")
}
func face(_ g: inout Grid, cx: Int, cy: Int, spread: Int, blush: Bool) {
    plot(&g, cx - spread, cy, "E")
    plot(&g, cx - spread, cy - 1, "E")
    plot(&g, cx + spread, cy, "E")
    plot(&g, cx + spread, cy - 1, "E")
    plot(&g, cx - spread, cy - 1, "e")  // 眼神光
    plot(&g, cx + spread, cy - 1, "e")
    plot(&g, cx, cy + 2, "M")
    plot(&g, cx - 1, cy + 2, "M")
    if blush {
        plot(&g, cx - spread - 1, cy + 1, "R")
        plot(&g, cx + spread + 1, cy + 1, "R")
    }
}

// 草系：圆润种子兽 + 头顶叶芽（终阶开花）
func drawSprout(_ scale: Int) -> Grid {
    var g = blank()
    let r = [5.0, 6.0, 7.0][scale]
    let cx = 12.0, cy = Double(H) - 3 - r
    fillEllipse(&g, cx, cy, r, r * 0.92, "A")
    shadeBody(&g, cx: cx, cy: cy, rx: r, ry: r * 0.92)
    fillEllipse(&g, cx, cy + r * 0.45, r * 0.5, r * 0.45, "W")  // 腹白
    // 脚
    plot(&g, Int(cx) - 3, H - 3, "S"); plot(&g, Int(cx) - 3, H - 2, "A")
    plot(&g, Int(cx) + 3, H - 3, "S"); plot(&g, Int(cx) + 3, H - 2, "A")
    // 叶芽
    let topY = Int(cy - r * 0.92)
    for i in 0...(2 + scale) { plot(&g, Int(cx), topY - i, "C") }
    if scale >= 1 { plot(&g, Int(cx) - 1, topY - 2, "C"); plot(&g, Int(cx) + 1, topY - 3, "C") }
    if scale >= 2 {  // 开花
        for (x, y) in [(-2, -3), (2, -3), (-3, -1), (3, -1), (0, -5)] {
            plot(&g, Int(cx) + x, topY + y, "D")
        }
        plot(&g, Int(cx), topY - 3, "y")  // 花心
    }
    face(&g, cx: Int(cx), cy: Int(cy) - 1, spread: 2 + scale / 2, blush: true)
    outline(&g)
    return g
}

// 火系：直立小火蜥 + 尾焰
func drawEmber(_ scale: Int) -> Grid {
    var g = blank()
    let r = [4.5, 5.2, 6.0][scale]
    let cx = 11.0, cy = Double(H) - 3 - r
    // 尾巴 + 尾焰（右下）
    for i in 0...(3 + scale) { plot(&g, Int(cx) + Int(r) + i / 2, Int(cy) + 2 + i, "A") }
    let tipX = Int(cx) + Int(r) + (3 + scale) / 2, tipY = Int(cy) + 2 + (3 + scale)
    plot(&g, tipX, tipY - 1, "C"); plot(&g, tipX, tipY - 2, "D"); plot(&g, tipX + 1, tipY - 1, "C")
    fillEllipse(&g, cx, cy, r, r, "A")
    shadeBody(&g, cx: cx, cy: cy, rx: r, ry: r)
    fillEllipse(&g, cx, cy + r * 0.4, r * 0.45, r * 0.5, "W")
    plot(&g, Int(cx) - 4, H - 3, "S"); plot(&g, Int(cx) - 4, H - 2, "A")
    plot(&g, Int(cx) + 2, H - 3, "S"); plot(&g, Int(cx) + 2, H - 2, "A")
    // 头顶火苗
    let topY = Int(cy - r)
    plot(&g, Int(cx), topY - 1, "C"); plot(&g, Int(cx), topY - 2, "D")
    if scale >= 2 {
        for (x, y) in [(-2, -1), (2, -1), (-1, -3), (1, -3), (0, -4)] { plot(&g, Int(cx) + x, topY + y, "C") }
        plot(&g, Int(cx), topY - 3, "D")
    }
    face(&g, cx: Int(cx), cy: Int(cy) - 1, spread: 2, blush: false)
    outline(&g)
    return g
}

// 水系：龟形，背甲 + 探头
func drawAqua(_ scale: Int) -> Grid {
    var g = blank()
    let r = [5.0, 6.0, 7.0][scale]
    let cx = 12.0, cy = Double(H) - 4 - r * 0.7
    // 背甲
    fillEllipse(&g, cx, cy, r, r * 0.75, "C")
    fillEllipse(&g, cx - r * 0.2, cy - r * 0.2, r * 0.6, r * 0.4, "D")  // 甲高光
    // 甲纹
    plot(&g, Int(cx), Int(cy), "S"); plot(&g, Int(cx) - 2, Int(cy) + 1, "S"); plot(&g, Int(cx) + 2, Int(cy) + 1, "S")
    // 头（左前）
    let hx = cx - r * 0.7, hy = cy + r * 0.35
    fillEllipse(&g, hx, hy, 3.0, 2.6, "A")
    fillEllipse(&g, hx, hy - 0.6, 2.4, 1.6, "B")
    plot(&g, Int(hx) - 1, Int(hy), "E"); plot(&g, Int(hx) - 1, Int(hy) - 1, "e")
    plot(&g, Int(hx) - 2, Int(hy) + 1, "M")
    // 四肢
    plot(&g, Int(cx) - 4, H - 4, "A"); plot(&g, Int(cx) - 4, H - 3, "S")
    plot(&g, Int(cx) + 4, H - 4, "A"); plot(&g, Int(cx) + 4, H - 3, "S")
    // 水滴
    plot(&g, Int(cx) + Int(r), Int(cy) - 2, "D"); plot(&g, Int(cx) + Int(r), Int(cy) - 3, "D")
    if scale >= 2 { fillEllipse(&g, cx, cy - r * 0.1, r * 0.5, r * 0.35, "D") }
    outline(&g)
    return g
}

let speciesList: [Species] = [
    Species(
        id: "sprout", name: "苗芽", element: "grass",
        palette: pal([
            "K": "#1c3a1a", "S": "#2f7d38", "A": "#46b04f", "B": "#78e072", "H": "#b6f5a0",
            "W": "#eafff0", "E": "#20301a", "e": "#ffffff", "M": "#8a3b2b", "R": "#ff9ec7",
            "C": "#6fd36a", "D": "#ff9ec7",
        ]), draw: drawSprout),
    Species(
        id: "ember", name: "火蜥", element: "fire",
        palette: pal([
            "K": "#5a2410", "S": "#c24a1e", "A": "#ef6a2a", "B": "#ff9a3c", "H": "#ffc27a",
            "W": "#fff0d8", "E": "#3a2213", "e": "#ffffff", "M": "#7a2f18", "R": "#ff8a8a",
            "C": "#ff5030", "D": "#ffd23c",
        ]), draw: drawEmber),
    Species(
        id: "aqua", name: "水龟", element: "water",
        palette: pal([
            "K": "#123a55", "S": "#2566a8", "A": "#2f7fd0", "B": "#5fbef0", "H": "#a9e2ff",
            "W": "#eaf7ff", "E": "#16324a", "e": "#ffffff", "M": "#1f5a7a", "R": "#8fd0ff",
            "C": "#2fd0c0", "D": "#bfeaff",
        ]), draw: drawAqua),
]
let stages = ["egg", "juvenile", "mature", "final"]

func drawEgg(_ sp: Species) -> Grid {
    var g = blank()
    let cx = 12.0, cy = 12.5
    fillEllipse(&g, cx, cy, 6.2, 7.4, "A")
    fillEllipse(&g, cx - 1.2, cy - 1.6, 4.4, 5.2, "H")
    fillEllipse(&g, cx, cy + 1.5, 5.4, 5.0, "B")
    for (x, y) in [(9, 9), (14, 11), (10, 15), (15, 7), (12, 13)] { plot(&g, x, y, "C") }
    outline(&g)
    return g
}

func base(_ sp: Species, _ stage: String) -> Grid {
    switch stage {
    case "egg": return drawEgg(sp)
    case "juvenile": return sp.draw(0)
    case "mature": return sp.draw(1)
    default: return sp.draw(2)
    }
}

// MARK: - 动画烘焙

struct Anim { let fps: Int; let loop: Bool; let frames: [[String]] }
func pseudo(_ n: Int) -> Int { (n &* 1103515245 &+ 12345) >> 8 & 0x7fff }

func idleAnim(_ base: Grid, egg: Bool) -> Anim {
    if egg {
        return Anim(fps: 3, loop: true, frames: [rows(shift(base, -1, 0)), rows(base), rows(shift(base, 1, 0)), rows(base)])
    }
    let up = shift(base, 0, -1)
    return Anim(fps: 3, loop: true, frames: [rows(base), rows(up), rows(closeEyes(up)), rows(base)])
}
func workingAnim(_ base: Grid, egg: Bool, accent: Character) -> Anim {
    if egg {
        return Anim(fps: 5, loop: true, frames: [rows(base), rows(shift(base, 1, -1)), rows(base), rows(shift(base, -1, -1))])
    }
    let s1: [(Int, Int, Character)] = [(20, 12, accent), (21, 13, "D")]
    let s2: [(Int, Int, Character)] = [(20, 11, "D"), (21, 12, accent), (22, 13, accent), (23, 12, "D")]
    return Anim(
        fps: 6, loop: true,
        frames: [rows(shift(base, -1, 0)), rows(overlay(shift(base, 1, 0), s1)), rows(overlay(shift(base, 3, 0), s2)), rows(shift(base, 1, 0))])
}
func waitingAnim(_ base: Grid, egg: Bool) -> Anim {
    if egg {
        return Anim(fps: 4, loop: true, frames: [rows(base), rows(shift(base, 0, -1)), rows(base), rows(shift(base, 0, -1))])
    }
    let wave: [(Int, Int, Character)] = [(4, 8, "B"), (3, 7, "B"), (3, 6, "B")]
    return Anim(
        fps: 5, loop: true,
        frames: [rows(base), rows(shift(base, 0, -3)), rows(overlay(shift(base, 0, -4), wave)), rows(shift(base, 0, -1))])
}
func completeAnim(_ base: Grid, egg: Bool) -> Anim {
    let conf: [Character] = ["p", "y", "c", "n"]
    let lift = [0, -3, -4, -3, -1, 0, 0, 0]
    var frames: [[String]] = []
    for i in 0..<lift.count {
        var g = shift(base, 0, lift[i])
        if egg && i >= 2 { g = overlay(g, [(12, 9, "y"), (10, 13, "y"), (15, 11, "c"), (12, 15, "y")]) }
        var cells: [(Int, Int, Character)] = []
        for k in 0..<10 {
            let s = pseudo(i &* 31 &+ k &* 7)
            cells.append((s % W, (k * 3 + i * 2) % H, conf[(s / 3) % 4]))
        }
        frames.append(rows(overlay(g, cells)))
    }
    return Anim(fps: 8, loop: false, frames: frames)
}

// MARK: - 输出模型

struct OutAnim: Codable { let fps: Int; let loop: Bool; let frames: [[String]] }
struct OutStage: Codable { let stage: String; let anims: [String: OutAnim] }
struct OutSpecies: Codable {
    let id: String; let name: String; let element: String
    let palette: [String: String]; let stages: [OutStage]
}
struct OutRoot: Codable { let schemaVersion: Int; let species: [OutSpecies] }

func outAnims(_ sp: Species, _ stage: String) -> [String: OutAnim] {
    let g = base(sp, stage)
    let egg = (stage == "egg")
    func c(_ a: Anim) -> OutAnim { OutAnim(fps: a.fps, loop: a.loop, frames: a.frames) }
    return [
        "idle": c(idleAnim(g, egg: egg)),
        "working": c(workingAnim(g, egg: egg, accent: "C")),
        "waiting": c(waitingAnim(g, egg: egg)),
        "complete": c(completeAnim(g, egg: egg)),
    ]
}

let root = OutRoot(
    schemaVersion: 1,
    species: speciesList.map { sp in
        OutSpecies(
            id: sp.id, name: sp.name, element: sp.element, palette: sp.palette,
            stages: stages.map { OutStage(stage: $0, anims: outAnims(sp, $0)) })
    })

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = repoRoot.appendingPathComponent("assets")
let docsDir = repoRoot.appendingPathComponent("docs")
try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let jsonData = try encoder.encode(root)
try jsonData.write(to: assetsDir.appendingPathComponent("pets.json"))
let jsonString = String(decoding: jsonData, as: UTF8.self)
try previewHTML(jsonString).write(
    to: docsDir.appendingPathComponent("pet-preview.html"), atomically: true, encoding: .utf8)

// PNG 接触表（肉眼校验）：3 物种 × 4 阶段的 idle 首帧
writeContactSheet(to: docsDir.appendingPathComponent("pet-sprites.png"))

print("wrote assets/pets.json (\(jsonData.count) bytes), docs/pet-preview.html, docs/pet-sprites.png")

// MARK: - PNG 接触表

func hexColor(_ hex: String) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = Int(s, radix: 16) ?? 0
    return CGColor(
        red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
        blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

func writeContactSheet(to url: URL) {
    let scale = 6, pad = 8
    let cellPx = W * scale + pad * 2
    let cols = stages.count, rowsN = speciesList.count
    let imgW = cols * cellPx, imgH = rowsN * cellPx
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: imgW, height: imgH, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: imgW, height: imgH))
    for (ri, sp) in speciesList.enumerated() {
        for (ci, st) in stages.enumerated() {
            let g = base(sp, st)
            let ox = ci * cellPx + pad
            let oy = (rowsN - 1 - ri) * cellPx + pad  // CG 原点在左下
            for y in 0..<H {
                for x in 0..<W where g[y][x] != "." {
                    guard let hex = sp.palette[String(g[y][x])] else { continue }
                    ctx.setFillColor(hexColor(hex))
                    let px = ox + x * scale
                    let py = oy + (H - 1 - y) * scale
                    ctx.fill(CGRect(x: px, y: py, width: scale, height: scale))
                }
            }
        }
    }
    guard let img = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - 预览页

func previewHTML(_ json: String) -> String {
    """
    <!DOCTYPE html>
    <html lang="zh-CN"><head><meta charset="UTF-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>agentmon 宠物预览</title>
    <style>
      body{margin:0;font-family:-apple-system,system-ui,"PingFang SC",sans-serif;background:#12141a;color:#e8eaed;text-align:center}
      h1{font-size:20px;margin:20px 0 4px} .muted{color:#9aa0aa;font-size:13px;margin:0 0 16px}
      .controls{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin:14px}
      select,button{background:#1c2029;color:#e8eaed;border:1px solid #2a2f3a;border-radius:8px;padding:8px 12px;font-size:14px}
      canvas{background:#0b0d12;border-radius:14px;image-rendering:pixelated;margin:10px auto;display:block;box-shadow:0 8px 30px rgba(0,0,0,.4)}
      footer{color:#6b7280;font-size:12px;margin:24px}
    </style></head><body>
    <h1>agentmon 宠物图鉴 · 动画预览</h1>
    <p class="muted">原创三系精灵示意（复古像素画风），非任何既有 IP</p>
    <div class="controls">
      <select id="sp"></select><select id="stage"></select><select id="anim"></select>
      <button id="play">⏸ 暂停</button>
      <select id="speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option></select>
    </div>
    <canvas id="c" width="360" height="360"></canvas>
    <footer>agentmon · <a style="color:#ff8a12" href="index.html">返回首页</a></footer>
    <script>
    const DATA = \(json);
    const cv=document.getElementById('c'), ctx=cv.getContext('2d'), $=id=>document.getElementById(id);
    let playing=true, fi=0, acc=0, last=0;
    const byId=id=>DATA.species.find(s=>s.id===id);
    function opts(sel,arr,fmt){sel.innerHTML='';arr.forEach(v=>{const o=document.createElement('option');o.value=fmt?v.v:v;o.textContent=fmt?v.t:v;sel.appendChild(o);});}
    opts($('sp'),DATA.species.map(s=>({v:s.id,t:s.name+' ('+s.element+')'})),true);
    const curSp=()=>byId($('sp').value);
    const curStage=()=>curSp().stages.find(s=>s.stage===$('stage').value);
    const curAnim=()=>curStage().anims[$('anim').value];
    function refillStage(){opts($('stage'),curSp().stages.map(s=>s.stage));}
    function refillAnim(){opts($('anim'),Object.keys(curStage().anims));}
    refillStage();refillAnim();
    $('sp').onchange=()=>{refillStage();refillAnim();fi=0;};
    $('stage').onchange=()=>{refillAnim();fi=0;};
    $('anim').onchange=()=>{fi=0;};
    $('play').onclick=()=>{playing=!playing;$('play').textContent=playing?'⏸ 暂停':'▶ 播放';};
    function draw(frame,pal){const G=frame.length,CELL=cv.width/G;ctx.clearRect(0,0,cv.width,cv.height);
      for(let y=0;y<frame.length;y++){const row=frame[y];for(let x=0;x<row.length;x++){const hex=pal[row[x]];if(hex){ctx.fillStyle=hex;ctx.fillRect(x*CELL,y*CELL,CELL+0.5,CELL+0.5);}}}}
    function loop(t){const a=curAnim(),sp=curSp(),speed=parseFloat($('speed').value);
      if(playing){acc+=(t-last)*speed;const dur=1000/a.fps;while(acc>=dur){acc-=dur;fi++;if(fi>=a.frames.length){fi=a.loop?0:a.frames.length-1;if(!a.loop)playing=false;}}}
      last=t;draw(a.frames[Math.min(fi,a.frames.length-1)],sp.palette);requestAnimationFrame(loop);}
    requestAnimationFrame(t=>{last=t;requestAnimationFrame(loop);});
    </script></body></html>
    """
}
