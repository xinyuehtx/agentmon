#!/usr/bin/env swift
//
// 处理用户提供的原创宠物精灵图集（6 帧横条 / 洋红底 / 黑分隔线）→ agentmon 可用的紧凑透明条 + manifest。
// 步骤：切 6 帧 → 抠洋红底为透明 → 跨 6 帧公共裁剪（保留位移动画）→ 缩放 → 写 PNG 条 + manifest.json
//
// 用法：swift scripts/process-packs.swift <源目录（含 *_pack 子目录）> [帧高=160]
// 输出：assets/pets_raster/<species>/<stage>_<state>.png  +  assets/pets_raster/manifest.json
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let srcDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "/tmp/agentmon-pets-src")
let frameH = args.count > 2 ? (Int(args[2]) ?? 160) : 160
let FRAMES = args.count > 3 ? (Int(args[3]) ?? 6) : 6  // 每个动作条的帧数（与生图输出一致）

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outDir = repoRoot.appendingPathComponent("assets/pets_raster")

// 文件名 action → agentmon 状态键
func stateKey(_ action: String) -> String? {
    switch action {
    case "idle": return "idle"
    case "attack": return "working"
    case "waiting": return "waiting"
    case "complete", "hatch": return "complete"
    default: return nil
    }
}
func elementOf(_ token: String) -> String {
    switch token {
    case "cabbage", "leaf", "grass", "plant": return "grass"
    case "fire", "flame", "ember": return "fire"
    case "water", "aqua", "sea": return "water"
    default: return token
    }
}
// 按「一轮秒数」推导 fps，使动作节奏与帧数无关（帧越多越平滑，而非越慢）。
func fps(_ state: String, frames: Int) -> Int {
    let cycle: Double
    switch state {
    case "working": cycle = 0.9
    case "complete": cycle = 1.2
    case "waiting": cycle = 0.9
    default: cycle = 1.4
    }
    return max(1, Int((Double(frames) / cycle).rounded()))
}

struct RGBA { var r: Int; var g: Int; var b: Int }

func loadPixels(_ url: URL) -> (px: [UInt8], w: Int, h: Int)? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    // 用「带 transform 的缩略图」加载以烘焙 EXIF 朝向（AI 图朝向不一致，否则会上下颠倒）
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 4096,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (px, w, h)
}

func makeCGImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
    var data = px
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    return ctx.makeImage()
}

func writePNG(_ img: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

// 处理单个动作条 → 写紧凑透明条 PNG，返回 (帧宽, 帧高)
func processStrip(_ url: URL, out: URL) -> (Int, Int)? {
    guard let (src, w, h) = loadPixels(url) else { return nil }
    // 背景色 = 四角中位（洋红）
    func at(_ x: Int, _ y: Int) -> RGBA {
        let i = (y * w + x) * 4
        return RGBA(r: Int(src[i]), g: Int(src[i + 1]), b: Int(src[i + 2]))
    }
    let corners = [at(2, 2), at(w - 3, 2), at(2, h - 3), at(w - 3, h - 3)]
    let bg = RGBA(
        r: corners.map(\.r).sorted()[1], g: corners.map(\.g).sorted()[1], b: corners.map(\.b).sorted()[1])
    let tol = 105.0  // 抠色容差

    var out8 = src
    func dist(_ p: RGBA) -> Double {
        let dr = Double(p.r - bg.r), dg = Double(p.g - bg.g), db = Double(p.b - bg.b)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
    // alpha 0..1：接近采样背景，或明显洋红（对背景深浅更鲁棒），并羽化边缘
    func bgAlpha(_ p: RGBA) -> Double {
        let magenta = p.r > 135 && p.b > 105 && p.g < min(p.r, p.b) - 35
        if magenta { return 0 }
        let d = dist(p)
        if d < tol { return 0 }
        if d < tol * 1.6 { return (d - tol) / (tol * 0.6) }
        return 1
    }
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let a = bgAlpha(RGBA(r: Int(src[i]), g: Int(src[i + 1]), b: Int(src[i + 2])))
            out8[i] = UInt8(Double(src[i]) * a)
            out8[i + 1] = UInt8(Double(src[i + 1]) * a)
            out8[i + 2] = UInt8(Double(src[i + 2]) * a)
            out8[i + 3] = UInt8(a * 255)
        }
    }

    let cellW = Double(w) / Double(FRAMES)
    // 去黑分隔线：把内部 cell 边界附近整列置透明（角色居中，不受影响）
    let divBand = max(2, Int(cellW * 0.02))
    for f in 1..<FRAMES {
        let bx = Int(Double(f) * cellW)
        for dxb in -divBand...divBand {
            let x = bx + dxb
            guard x >= 0, x < w else { continue }
            for y in 0..<h { out8[(y * w + x) * 4 + 3] = 0 }
        }
    }

    // 各帧内容 bbox（整格宽度，不做 margin 裁剪 → 不截断特效）
    let cw = Int(cellW)
    func alpha(_ gx: Int, _ gy: Int) -> Int { Int(out8[(gy * w + gx) * 4 + 3]) }
    var uMinX = cw, uMinY = h, uMaxX = 0, uMaxY = 0
    for f in 0..<FRAMES {
        let x0 = Int(Double(f) * cellW)
        for ly in 0..<h {
            for lx in 0..<cw where x0 + lx < w && alpha(x0 + lx, ly) > 40 {
                uMinX = min(uMinX, lx); uMaxX = max(uMaxX, lx)
                uMinY = min(uMinY, ly); uMaxY = max(uMaxY, ly)
            }
        }
    }
    guard uMaxX > uMinX, uMaxY > uMinY else { return nil }
    // 四周留 2% 内边距，避免特效贴边被切
    let padX = Int(Double(cw) * 0.02), padY = Int(Double(h) * 0.02)
    uMinX = max(0, uMinX - padX); uMaxX = min(cw - 1, uMaxX + padX)
    uMinY = max(0, uMinY - padY); uMaxY = min(h - 1, uMaxY + padY)
    let uw = uMaxX - uMinX + 1, uh = uMaxY - uMinY + 1

    guard let keyed = makeCGImage(out8, w, h) else { return nil }
    let scale = Double(frameH) / Double(uh)
    let fw = max(1, Int(Double(uw) * scale))
    let stripW = fw * FRAMES
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let octx = CGContext(data: nil, width: stripW, height: frameH, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    octx.interpolationQuality = .high
    for f in 0..<FRAMES {
        let gx = Int(Double(f) * cellW) + uMinX
        let gy = uMinY
        guard let frame = keyed.cropping(to: CGRect(x: gx, y: gy, width: uw, height: uh)) else { continue }
        octx.draw(frame, in: CGRect(x: f * fw, y: 0, width: fw, height: frameH))
    }
    guard let stripImg = octx.makeImage() else { return nil }
    writePNG(stripImg, out)
    return (fw, frameH)
}

// MARK: - 遍历

struct ActionOut: Codable { let file: String; let frames: Int; let fw: Int; let fh: Int; let fps: Int }
struct StageOut: Codable { let stage: String; var actions: [String: ActionOut] }
struct SpeciesOut: Codable { let id: String; let element: String; var stages: [StageOut] }
struct Manifest: Codable { let schemaVersion: Int; let frameHeight: Int; let species: [SpeciesOut] }

let fm = FileManager.default
try? fm.removeItem(at: outDir)
let stageOrder = ["egg", "juvenile", "mature", "final"]
var speciesMap: [String: (element: String, stages: [String: [String: ActionOut]])] = [:]

let packs = (try? fm.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil))?
    .filter { $0.hasDirectoryPath } ?? []
for pack in packs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    let files = (try? fm.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil))?
        .filter { $0.pathExtension == "png" && !$0.lastPathComponent.contains("evolution") } ?? []
    for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let base = file.deletingPathExtension().lastPathComponent
        let toks = base.split(separator: "_").map(String.init)
        guard toks.count >= 4, let state = stateKey(toks[toks.count - 1]) else { continue }
        let stage = toks[toks.count - 2]
        guard stageOrder.contains(stage) else { continue }
        let speciesID = toks[0..<(toks.count - 2)].joined(separator: "_")
        let element = elementOf(toks.count >= 2 ? toks[1] : "")
        let outFile = outDir.appendingPathComponent("\(speciesID)/\(stage)_\(state).png")
        guard let (fw, fh) = processStrip(file, out: outFile) else {
            print("skip \(base)"); continue
        }
        let action = ActionOut(
            file: "\(speciesID)/\(stage)_\(state).png", frames: FRAMES, fw: fw, fh: fh,
            fps: fps(state, frames: FRAMES))
        speciesMap[speciesID, default: (element, [:])].element = element
        speciesMap[speciesID, default: (element, [:])].stages[stage, default: [:]][state] = action
        print("ok \(speciesID) \(stage)/\(state)  \(fw)x\(fh)")
    }
}

let manifest = Manifest(
    schemaVersion: 1, frameHeight: frameH,
    species: speciesMap.keys.sorted().map { id in
        let (element, stages) = speciesMap[id]!
        return SpeciesOut(
            id: id, element: element,
            stages: stageOrder.compactMap { st in stages[st].map { StageOut(stage: st, actions: $0) } })
    })
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
let mjson = try enc.encode(manifest)
try mjson.write(to: outDir.appendingPathComponent("manifest.json"))
print("\nwrote \(outDir.path)/manifest.json  species=\(manifest.species.map(\.id))")

// 联系表（每物种×阶段的 idle 首帧）→ docs/pet-sprites.png，供官网图鉴展示
func contactSheet() {
    let cell = frameH + 24
    let cols = stageOrder.count, rowsN = manifest.species.count
    guard rowsN > 0 else { return }
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: cols * cell, height: rowsN * cell, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: cols * cell, height: rowsN * cell))
    ctx.interpolationQuality = .high
    for (ri, sp) in manifest.species.enumerated() {
        for (ci, st) in stageOrder.enumerated() {
            guard let stage = sp.stages.first(where: { $0.stage == st }),
                let a = stage.actions["idle"] ?? stage.actions.values.first,
                let src = CGImageSourceCreateWithURL(outDir.appendingPathComponent(a.file) as CFURL, nil),
                let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
                let f0 = img.cropping(to: CGRect(x: 0, y: 0, width: img.width / max(1, a.frames), height: img.height))
            else { continue }
            let iw = Double(f0.width), ih = Double(f0.height)
            let s = min(Double(cell - 16) / iw, Double(cell - 16) / ih)
            let w = iw * s, h = ih * s
            let ox = Double(ci * cell) + (Double(cell) - w) / 2
            let oy = Double((rowsN - 1 - ri) * cell) + (Double(cell) - h) / 2  // CG 原点左下
            ctx.draw(f0, in: CGRect(x: ox, y: oy, width: w, height: h))
        }
    }
    guard let out = ctx.makeImage() else { return }
    let url = repoRoot.appendingPathComponent("docs/pet-sprites.png")
    if let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        print("wrote docs/pet-sprites.png")
    }
}
contactSheet()

// 光栅动画预览页（内联清单，逐帧播放；图片先找 docs/pets_raster，再回退 ../assets/pets_raster）
try? rasterPreviewHTML(String(decoding: mjson, as: UTF8.self))
    .write(to: repoRoot.appendingPathComponent("docs/pet-preview.html"), atomically: true, encoding: .utf8)
print("wrote docs/pet-preview.html")

func rasterPreviewHTML(_ json: String) -> String {
    """
    <!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>agentmon 宠物预览</title>
    <style>
      body{margin:0;font-family:-apple-system,system-ui,"PingFang SC",sans-serif;background:#12141a;color:#e8eaed;text-align:center}
      h1{font-size:20px;margin:20px 0 4px}.muted{color:#9aa0aa;font-size:13px;margin:0 0 12px}
      .controls{display:flex;gap:8px;justify-content:center;flex-wrap:wrap;margin:12px}
      select,button{background:#1c2029;color:#e8eaed;border:1px solid #2a2f3a;border-radius:8px;padding:8px 12px;font-size:14px}
      canvas{background:radial-gradient(circle at 50% 42%,#1b2030,#0b0d12);border-radius:16px;margin:10px auto;display:block;box-shadow:0 8px 30px rgba(0,0,0,.4)}
      footer{color:#6b7280;font-size:12px;margin:24px}
    </style></head><body>
    <h1>agentmon 宠物图鉴 · 动画预览</h1>
    <p class="muted">原创手绘图集（逐帧动画），非任何既有 IP</p>
    <div class="controls">
      <select id="sp"></select><select id="stage"></select><select id="action"></select>
      <button id="play">⏸ 暂停</button>
      <select id="speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option></select>
    </div>
    <canvas id="c" width="320" height="320"></canvas>
    <footer>agentmon · <a style="color:#ff8a12" href="index.html">返回首页</a></footer>
    <script>
    var M=\(json);
    var cv=document.getElementById('c'),ctx=cv.getContext('2d'),$=function(i){return document.getElementById(i);};
    var playing=true,t0=performance.now(),imgs={};
    function imgFor(file){ if(imgs[file])return imgs[file]; var im=new Image(); im.onerror=function(){ if(!im._alt){im._alt=1; im.src='../assets/pets_raster/'+file;} }; im.src='pets_raster/'+file; imgs[file]=im; return im; }
    function spById(id){ for(var i=0;i<M.species.length;i++) if(M.species[i].id===id) return M.species[i]; }
    function opts(sel,arr){ sel.innerHTML=''; arr.forEach(function(v){ var o=document.createElement('option'); o.value=v; o.textContent=v; sel.appendChild(o); }); }
    function curSp(){ return spById($('sp').value); }
    function curStage(){ var s=curSp().stages; for(var i=0;i<s.length;i++) if(s[i].stage===$('stage').value) return s[i]; }
    function curAction(){ return curStage().actions[$('action').value]; }
    opts($('sp'), M.species.map(function(s){return s.id;}));
    function refillStage(){ opts($('stage'), curSp().stages.map(function(s){return s.stage;})); }
    function refillAction(){ opts($('action'), Object.keys(curStage().actions)); }
    refillStage(); refillAction();
    $('sp').onchange=function(){refillStage();refillAction();reset();};
    $('stage').onchange=function(){refillAction();reset();};
    $('action').onchange=reset;
    $('play').onclick=function(){playing=!playing;$('play').textContent=playing?'⏸ 暂停':'▶ 播放';};
    function reset(){t0=performance.now();}
    function frame(now){
      var a=curAction(), speed=parseFloat($('speed').value);
      var el=(now-t0)/1000*speed, loop=($('action').value!=='complete');
      var n=a.frames, cycle=n/Math.max(1,a.fps);
      var u = loop ? ((el % cycle)/cycle)*n : Math.min(el/cycle,0.999)*Math.max(1,n-1);
      var i=Math.min(Math.floor(u),n-1), ni=loop?((i+1)%n):Math.min(i+1,n-1), fr=u-Math.floor(u);
      var im=imgFor(a.file);
      ctx.clearRect(0,0,cv.width,cv.height);
      if(im.complete&&im.naturalWidth>0){
        var s=Math.min(cv.width/a.fw, cv.height/a.fh)*0.92, dw=a.fw*s, dh=a.fh*s, dx=(cv.width-dw)/2, dy=cv.height-dh-8;
        ctx.globalAlpha=1; ctx.drawImage(im, i*a.fw,0,a.fw,a.fh, dx,dy,dw,dh);
        if(fr>0.001){ ctx.globalAlpha=fr; ctx.drawImage(im, ni*a.fw,0,a.fw,a.fh, dx,dy,dw,dh); }
        ctx.globalAlpha=1;
      }
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    </script></body></html>
    """
}
