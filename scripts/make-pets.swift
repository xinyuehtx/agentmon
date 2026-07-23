#!/usr/bin/env swift
//
// 生成 agentmon 宠物「矢量木偶」+ 动画数据（离屏纯数据 + PNG 快照，无需 GUI）。
// 原创三系精灵（草/火/水），平滑卡通风（圆润软阴影 + squash/stretch + 粒子特效），非任何既有 IP。
// 每状态含多个可随机替换的动作变体（例：攻击 = 水枪 / 泡泡）。
//
// 用法（仓库根目录）：  swift scripts/make-pets.swift
// 产出：assets/pets.json(schemaVersion 2) · docs/pet-preview.html · docs/pet-sprites.png
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let VB = 64.0  // viewBox 边长（浮点，分辨率无关）

// MARK: - 输出模型（Core 会镜像解码）

struct KF: Codable {
    var t: Double
    var dx = 0.0
    var dy = 0.0
    var sx = 1.0
    var sy = 1.0
    var rot = 0.0
    var a = 1.0
    var ease = "inout"  // linear|in|out|inout|back|elastic
}
struct Part: Codable {
    var name: String
    var kind: String  // "ellipse" | "poly"
    var cx = 0.0
    var cy = 0.0
    var rx = 0.0
    var ry = 0.0
    var rot = 0.0
    var points: [[Double]]? = nil
    var fill: String
    var stroke: String? = nil
    var strokeW = 0.0
}
struct Emitter: Codable {
    var kind: String  // droplet|bubble|ember|spark|leaf|seed|confetti|zzz
    var t0: Double
    var t1: Double
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var gravity: Double
    var count: Int
    var life: Double
    var size: Double
    var color: String
}
struct Variant: Codable {
    var id: String
    var dur: Double
    var loop: Bool
    var root: [KF]
    var tracks: [String: [KF]]
    var emitters: [Emitter]
}
struct StageOut: Codable {
    var stage: String
    var viewBox: Double
    var parts: [Part]
    var states: [String: [Variant]]
}
struct SpeciesOut: Codable {
    var id: String
    var name: String
    var element: String
    var palette: [String: String]
    var stages: [StageOut]
}
struct RootOut: Codable { var schemaVersion: Int; var species: [SpeciesOut] }

// MARK: - 作者化助手

func k(_ t: Double, dx: Double = 0, dy: Double = 0, sx: Double = 1, sy: Double = 1, rot: Double = 0, a: Double = 1, ease: String = "inout") -> KF {
    KF(t: t, dx: dx, dy: dy, sx: sx, sy: sy, rot: rot, a: a, ease: ease)
}
func ell(_ name: String, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ fill: String, stroke: String? = nil, sw: Double = 0, rot: Double = 0) -> Part {
    Part(name: name, kind: "ellipse", cx: cx, cy: cy, rx: rx, ry: ry, rot: rot, fill: fill, stroke: stroke, strokeW: sw)
}
func poly(_ name: String, _ pts: [[Double]], _ fill: String, stroke: String? = nil, sw: Double = 0) -> Part {
    Part(name: name, kind: "poly", points: pts, fill: fill, stroke: stroke, strokeW: sw)
}

// MARK: - 调色板（每物种）

func palette(_ element: String) -> [String: String] {
    var base: [String: String]
    switch element {
    case "grass":
        base = ["K": "#1d3a1f", "A": "#4fb257", "S": "#2f7d38", "H": "#8ee87f", "W": "#eafff0",
                "E": "#22301b", "e": "#ffffff", "M": "#7a3324", "R": "#ff9ec7", "C": "#57c85a", "D": "#ff9ec7"]
    case "fire":
        base = ["K": "#5a2410", "A": "#ef6a2a", "S": "#c24a1e", "H": "#ffc27a", "W": "#fff0d8",
                "E": "#3a2213", "e": "#ffffff", "M": "#7a2f18", "R": "#ff8a8a", "C": "#ff5030", "D": "#ffd23c"]
    default:
        base = ["K": "#123a55", "A": "#2f7fd0", "S": "#2566a8", "H": "#a9e2ff", "W": "#eaf7ff",
                "E": "#16324a", "e": "#ffffff", "M": "#1f5a7a", "R": "#8fd0ff", "C": "#2fd0c0", "D": "#bfeaff"]
    }
    // 彩带颜色（complete 共用）
    for (kk, v) in ["p": "#ff6fb5", "y": "#ffd23c", "n": "#7be07b", "b": "#5fe0ff"] { base[kk] = v }
    return base
}

// MARK: - Rig（基础姿势，部件 back→front）

// scale: 0 juvenile / 1 mature / 2 final
func rig(element: String, scale: Int) -> [Part] {
    let r = [15.0, 18.0, 21.0][scale]
    let cx = 32.0
    let cy = 56.0 - r  // 底部约在 y=56
    var p: [Part] = []

    // 元素背景件
    if element == "fire" {  // 尾巴 + 尾焰
        let tx = cx + r * 0.8, ty = cy + r * 0.5
        p.append(poly("tail", [[tx, ty], [tx + 8, ty + 6], [tx + 3, ty + 10], [tx - 2, ty + 6]], "A", stroke: "K", sw: 1.5))
        p.append(ell("tailflame", tx + 6, ty + 10, 3, 4, "C", stroke: nil))
        p.append(ell("tailflame2", tx + 6, ty + 9, 1.6, 2.4, "D"))
    }
    if element == "water" {  // 背甲
        p.append(ell("shell", cx, cy - r * 0.1, r * 1.02, r * 0.92, "C", stroke: "K", sw: 2))
        p.append(ell("shellHi", cx - r * 0.3, cy - r * 0.4, r * 0.5, r * 0.32, "D"))
    }

    // 腿
    p.append(ell("legL", cx - r * 0.5, 56, 4, 3.4, "S", stroke: "K", sw: 1.5))
    p.append(ell("legR", cx + r * 0.5, 56, 4, 3.4, "S", stroke: "K", sw: 1.5))

    // 身体 + 明暗
    p.append(ell("body", cx, cy, r, r * 0.98, "A", stroke: "K", sw: 2.4))
    p.append(ell("bodyShadow", cx, cy + r * 0.42, r * 0.82, r * 0.5, "S"))
    p.append(ell("bodyHi", cx - r * 0.3, cy - r * 0.34, r * 0.55, r * 0.42, "H"))
    p.append(ell("belly", cx, cy + r * 0.34, r * 0.5, r * 0.46, "W"))

    // 手臂（armR 用于招手）
    p.append(ell("armL", cx - r * 0.92, cy + r * 0.2, 3.6, 5, "A", stroke: "K", sw: 1.5))
    p.append(ell("armR", cx + r * 0.92, cy + r * 0.2, 3.6, 5, "A", stroke: "K", sw: 1.5))

    // 元素头饰
    let topY = cy - r * 0.98
    switch element {
    case "grass":
        p.append(poly("leaf", [[cx, topY - 10 - Double(scale) * 2], [cx - 5, topY - 1], [cx + 5, topY - 1]], "C", stroke: "K", sw: 1.5))
        if scale >= 1 {
            p.append(poly("leafL", [[cx - 9, topY - 6], [cx - 2, topY], [cx - 4, topY + 3]], "C", stroke: "K", sw: 1))
            p.append(poly("leafR", [[cx + 9, topY - 6], [cx + 2, topY], [cx + 4, topY + 3]], "C", stroke: "K", sw: 1))
        }
        if scale >= 2 {
            for (i, off) in [-6.0, 0.0, 6.0].enumerated() {
                p.append(ell("flower\(i)", cx + off, topY - 8, 3.2, 3.2, "D", stroke: "K", sw: 1))
            }
            p.append(ell("flowerC", cx, topY - 8, 1.4, 1.4, "y"))
        }
    case "fire":
        p.append(poly("flame", [[cx, topY - 9 - Double(scale) * 2], [cx - 4, topY], [cx + 4, topY]], "C", stroke: "K", sw: 1.5))
        p.append(poly("flame2", [[cx, topY - 6], [cx - 2, topY - 1], [cx + 2, topY - 1]], "D"))
    default:
        p.append(ell("drop", cx, topY - 3, 3, 4.2, "D", stroke: "K", sw: 1.2))
    }

    // 脸
    let ey = cy - r * 0.22
    let esp = r * 0.42
    p.append(ell("eyeL", cx - esp, ey, 2.6, 3.4, "E"))
    p.append(ell("eyeR", cx + esp, ey, 2.6, 3.4, "E"))
    p.append(ell("shineL", cx - esp + 0.9, ey - 1.1, 0.9, 1.1, "e"))
    p.append(ell("shineR", cx + esp + 0.9, ey - 1.1, 0.9, 1.1, "e"))
    p.append(ell("cheekL", cx - esp - 1.6, ey + 3.4, 1.8, 1.2, "R"))
    p.append(ell("cheekR", cx + esp + 1.6, ey + 3.4, 1.8, 1.2, "R"))
    p.append(poly("mouth", [[cx - 2.4, ey + 3.2], [cx + 2.4, ey + 3.2], [cx, ey + 5.4]], "M"))
    return p
}

func eggRig(_ element: String) -> [Part] {
    let cx = 32.0, cy = 33.0
    var p: [Part] = []
    p.append(ell("egg", cx, cy, 15, 18, "A", stroke: "K", sw: 2.4))
    p.append(ell("eggShadow", cx, cy + 7, 12, 9, "S"))
    p.append(ell("eggHi", cx - 4, cy - 6, 8, 6, "H"))
    for (i, pt) in [[-6.0, -4], [7, 2], [-3, 8], [6, -7]].enumerated() {
        p.append(ell("spot\(i)", cx + pt[0], cy + pt[1], 2.2, 2.2, "C"))
    }
    return p
}

// MARK: - 动作模板（返回 root 轨 + 部件轨）

func blinkTrack() -> [KF] { [k(0), k(0.86), k(0.9, sy: 0.12), k(0.94), k(1)] }
func armBob() -> [KF] { [k(0), k(0.5, dy: -0.6, rot: -3), k(1)] }

func breathe() -> ([KF], [String: [KF]]) {
    (
        [k(0, sy: 1), k(0.5, dy: -0.9, sy: 1.05), k(1, sy: 1)],
        ["eyeL": blinkTrack(), "eyeR": blinkTrack(), "armL": armBob(), "armR": armBob()]
    )
}
func sleep() -> ([KF], [String: [KF]]) {
    let closed: [KF] = [k(0, sy: 0.12), k(1, sy: 0.12)]
    return (
        [k(0, dy: 3, sy: 1.06), k(0.5, dy: 4.4, sy: 1.1), k(1, dy: 3, sy: 1.06)],
        ["eyeL": closed, "eyeR": closed]
    )
}
func roll() -> ([KF], [String: [KF]]) {
    ([k(0, rot: 0, ease: "in"), k(0.5, dy: -3, sy: 0.94, rot: 180, ease: "out"), k(1, rot: 360, ease: "in")], [:])
}
func hop() -> ([KF], [String: [KF]]) {
    (
        [
            k(0, sy: 1, ease: "in"),
            k(0.16, dy: 2.5, sy: 1.18, ease: "out"),  // 下蹲预备
            k(0.44, dy: -17, sy: 0.88, ease: "out"),  // 蹦起拉伸
            k(0.68, dy: 0, sy: 1.16, ease: "back"),  // 落地压扁（回弹）
            k(0.84, dy: 0, sy: 0.96, ease: "out"),
            k(1, sy: 1, ease: "inout"),
        ], [:]
    )
}
func wave() -> ([KF], [String: [KF]]) {
    let arm: [KF] = [
        k(0, rot: 0, ease: "out"), k(0.18, rot: -85, ease: "out"), k(0.36, rot: -50, ease: "inout"),
        k(0.54, rot: -88, ease: "inout"), k(0.72, rot: -50, ease: "inout"), k(0.88, rot: -80, ease: "inout"),
        k(1, rot: 0, ease: "in"),
    ]
    return ([k(0), k(0.5, dy: -1.6, rot: -4, ease: "inout"), k(1)], ["armR": arm])
}
func lunge() -> ([KF], [String: [KF]]) {
    let arm: [KF] = [k(0, rot: 0, ease: "in"), k(0.3, rot: 55, ease: "out"), k(0.5, rot: 10, ease: "back"), k(1, rot: 0)]
    return (
        [
            k(0, ease: "in"),
            k(0.18, dx: -6, sx: 1.07, ease: "in"),  // 蓄力后仰
            k(0.32, dx: 12, sx: 0.9, sy: 1.08, ease: "out"),  // 前冲出招
            k(0.5, dx: 2, ease: "back"),  // 回弹
            k(1, ease: "inout"),
        ], ["armR": arm]
    )
}
func cheer() -> ([KF], [String: [KF]]) {
    let up: [KF] = [k(0, rot: 0, ease: "out"), k(0.3, rot: -130, ease: "back"), k(0.7, rot: -110), k(1, rot: -120)]
    let upR: [KF] = [k(0, rot: 0, ease: "out"), k(0.3, rot: 130, ease: "back"), k(0.7, rot: 110), k(1, rot: 120)]
    return (
        [
            k(0, sy: 1, ease: "in"), k(0.2, dy: 2, sy: 1.14, ease: "out"),
            k(0.5, dy: -17, sy: 0.88, ease: "out"), k(0.72, dy: 0, sy: 1.18, ease: "back"),
            k(0.86, dy: 0, sy: 0.95, ease: "out"), k(1, dy: 0, sy: 1),
        ], ["armL": up, "armR": upR]
    )
}
func eggWobble() -> ([KF], [String: [KF]]) {
    ([k(0, rot: -5, ease: "inout"), k(0.5, rot: 5, ease: "inout"), k(1, rot: -5, ease: "inout")], [:])
}

// MARK: - 粒子发射器（按元素/变体）

func emitter(_ kind: String, color: String, x: Double = 40, y: Double = 30,
             vx: Double, vy: Double, gravity: Double, count: Int, life: Double, size: Double,
             t0: Double = 0.3, t1: Double = 0.95) -> Emitter {
    Emitter(kind: kind, t0: t0, t1: t1, x: x, y: y, vx: vx, vy: vy, gravity: gravity, count: count, life: life, size: size, color: color)
}

/// working 状态的元素攻击变体（返回 [(variantID, emitters)]）
func attackVariants(_ element: String) -> [(String, [Emitter])] {
    switch element {
    case "grass":
        return [
            ("leafblade", [emitter("leaf", color: "C", vx: 30, vy: -16, gravity: 26, count: 8, life: 0.9, size: 3.2)]),
            ("seedshot", [emitter("seed", color: "A", vx: 27, vy: -20, gravity: 42, count: 9, life: 0.8, size: 2.2)]),
        ]
    case "fire":
        return [
            ("flare", [emitter("ember", color: "C", vx: 30, vy: -8, gravity: 26, count: 14, life: 0.65, size: 2.4)]),
            ("sparks", [emitter("spark", color: "D", x: 36, y: 26, vx: 6, vy: -30, gravity: 20, count: 14, life: 0.7, size: 1.8)]),
        ]
    default:
        return [
            ("watergun", [emitter("droplet", color: "D", vx: 36, vy: -6, gravity: 44, count: 16, life: 0.7, size: 2.4)]),
            ("bubbles", [emitter("bubble", color: "D", x: 40, y: 28, vx: 12, vy: -24, gravity: -3, count: 11, life: 1.0, size: 2.8, t0: 0.15, t1: 1.0)]),
        ]
    }
}

// MARK: - 组装 states

func variant(_ id: String, _ dur: Double, _ loop: Bool, _ motion: ([KF], [String: [KF]]), _ emitters: [Emitter] = []) -> Variant {
    Variant(id: id, dur: dur, loop: loop, root: motion.0, tracks: motion.1, emitters: emitters)
}

func states(element: String, egg: Bool) -> [String: [Variant]] {
    if egg {
        let zzz = emitter("zzz", color: "W", x: 40, y: 16, vx: 4, vy: -8, gravity: 0, count: 3, life: 1.6, size: 3, t0: 0, t1: 3)
        return [
            "idle": [variant("wobble", 2.2, true, eggWobble()), variant("nap", 3.0, true, eggWobble(), [zzz])],
            "working": [variant("shiver", 0.6, true, ([k(0, dx: -1), k(0.5, dx: 1), k(1, dx: -1)], [:]))],
            "waiting": [variant("rock", 1.4, true, eggWobble())],
            "complete": [variant("hatch", 1.4, false, ([k(0, sy: 1), k(0.4, sy: 1.12), k(0.7, dy: -4, sy: 0.94), k(1, sy: 1)], [:]),
                [emitter("confetti", color: "p", x: 32, y: 8, vx: 0, vy: 10, gravity: 12, count: 22, life: 1.2, size: 2.6, t0: 0.2, t1: 0.6),
                 emitter("spark", color: "y", x: 32, y: 30, vx: 0, vy: -14, gravity: 8, count: 10, life: 0.8, size: 2, t0: 0.3, t1: 0.7)])],
        ]
    }
    let atks = attackVariants(element)
    let confetti = emitter("confetti", color: "p", x: 32, y: 8, vx: 0, vy: 12, gravity: 12, count: 26, life: 1.3, size: 2.6, t0: 0.1, t1: 0.55)
    return [
        "idle": [variant("breathe", 2.4, true, breathe()), variant("sleep", 3.2, true, sleep()), variant("roll", 1.4, true, roll())],
        "working": atks.map { variant($0.0, 1.0, true, lunge(), $0.1) },
        "waiting": [variant("wave", 1.0, true, wave()), variant("hop", 0.9, true, hop())],
        "complete": [variant("cheer", 1.3, false, cheer()), variant("confetti", 1.3, false, hop(), [confetti])],
    ]
}

// MARK: - 生成

let elements = [("sprout", "苗芽", "grass"), ("ember", "火蜥", "fire"), ("aqua", "水龟", "water")]
let stageNames = ["egg", "juvenile", "mature", "final"]

func stageOut(_ element: String, _ stage: String) -> StageOut {
    let egg = (stage == "egg")
    let parts: [Part]
    switch stage {
    case "egg": parts = eggRig(element)
    case "juvenile": parts = rig(element: element, scale: 0)
    case "mature": parts = rig(element: element, scale: 1)
    default: parts = rig(element: element, scale: 2)
    }
    return StageOut(stage: stage, viewBox: VB, parts: parts, states: states(element: element, egg: egg))
}

let root = RootOut(
    schemaVersion: 2,
    species: elements.map { (id, name, element) in
        SpeciesOut(id: id, name: name, element: element, palette: palette(element),
                   stages: stageNames.map { stageOut(element, $0) })
    })

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetsDir = repoRoot.appendingPathComponent("assets")
let docsDir = repoRoot.appendingPathComponent("docs")
try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
let jsonData = try enc.encode(root)
try jsonData.write(to: assetsDir.appendingPathComponent("pets.json"))
try previewHTML(String(decoding: jsonData, as: UTF8.self)).write(
    to: docsDir.appendingPathComponent("pet-preview.html"), atomically: true, encoding: .utf8)
writeContactSheet(to: docsDir.appendingPathComponent("pet-sprites.png"))
print("wrote assets/pets.json (\(jsonData.count) bytes), docs/pet-preview.html, docs/pet-sprites.png")

// MARK: - PNG 快照（基础姿势，肉眼校验 rig 造型）

func cg(_ hex: String) -> CGColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = Int(s, radix: 16) ?? 0
    return CGColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

func writeContactSheet(to url: URL) {
    let scale = 5, pad = 6
    let cell = Int(VB) * scale + pad * 2
    let cols = stageNames.count, rowsN = elements.count
    let imgW = cols * cell, imgH = rowsN * cell
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: imgW, height: imgH, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: imgW, height: imgH))
    ctx.setLineJoin(.round)
    for (ri, sp) in elements.enumerated() {
        let pal = palette(sp.2)
        for (ci, st) in stageNames.enumerated() {
            let parts = stageOut(sp.2, st).parts
            let ox = Double(ci * cell + pad)
            let oyTop = Double((rowsN - 1 - ri) * cell + pad)  // CG 原点左下
            func fx(_ x: Double) -> CGFloat { CGFloat(ox + x * Double(scale)) }
            func fy(_ y: Double) -> CGFloat { CGFloat(oyTop + (VB - y) * Double(scale)) }  // 翻转 y
            for part in parts {
                guard let fillHex = pal[part.fill] else { continue }
                let path = CGMutablePath()
                if part.kind == "ellipse" {
                    let rect = CGRect(x: fx(part.cx - part.rx), y: fy(part.cy + part.ry), width: CGFloat(part.rx * 2 * Double(scale)), height: CGFloat(part.ry * 2 * Double(scale)))
                    path.addEllipse(in: rect)
                } else if let pts = part.points {
                    path.move(to: CGPoint(x: fx(pts[0][0]), y: fy(pts[0][1])))
                    for p in pts.dropFirst() { path.addLine(to: CGPoint(x: fx(p[0]), y: fy(p[1]))) }
                    path.closeSubpath()
                }
                ctx.addPath(path)
                ctx.setFillColor(cg(fillHex))
                ctx.fillPath()
                if let sHex = part.stroke.flatMap({ pal[$0] }), part.strokeW > 0 {
                    ctx.addPath(path)
                    ctx.setStrokeColor(cg(sHex))
                    ctx.setLineWidth(CGFloat(part.strokeW * Double(scale)))
                    ctx.strokePath()
                }
            }
        }
    }
    guard let img = ctx.makeImage(),
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

// MARK: - 预览页（JS 矢量渲染器）

func previewHTML(_ json: String) -> String {
    """
    <!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <title>agentmon 宠物预览</title>
    <style>
      body{margin:0;font-family:-apple-system,system-ui,"PingFang SC",sans-serif;background:#12141a;color:#e8eaed;text-align:center}
      h1{font-size:20px;margin:20px 0 4px}.muted{color:#9aa0aa;font-size:13px;margin:0 0 12px}
      .controls{display:flex;gap:8px;justify-content:center;flex-wrap:wrap;margin:12px}
      select,button{background:#1c2029;color:#e8eaed;border:1px solid #2a2f3a;border-radius:8px;padding:8px 12px;font-size:14px}
      canvas{background:radial-gradient(circle at 50% 40%,#1b2030,#0b0d12);border-radius:16px;margin:10px auto;display:block;box-shadow:0 8px 30px rgba(0,0,0,.4)}
      footer{color:#6b7280;font-size:12px;margin:24px}
    </style></head><body>
    <h1>agentmon 宠物图鉴 · 动画预览</h1>
    <p class="muted">原创三系精灵（平滑卡通风），非任何既有 IP</p>
    <div class="controls">
      <select id="sp"></select><select id="stage"></select><select id="state"></select><select id="variant"></select>
      <button id="play">⏸ 暂停</button>
      <select id="speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option></select>
    </div>
    <canvas id="c" width="360" height="360"></canvas>
    <footer>agentmon · <a style="color:#ff8a12" href="index.html">返回首页</a></footer>
    <script>
    const DATA=\(json), VB=64;
    const cv=document.getElementById('c'),ctx=cv.getContext('2d'),$=id=>document.getElementById(id);
    let playing=true,t0=performance.now();
    const byId=id=>DATA.species.find(s=>s.id===id);
    function opts(sel,arr,fmt){sel.innerHTML='';arr.forEach(v=>{const o=document.createElement('option');o.value=fmt?v.v:v;o.textContent=fmt?v.t:v;sel.appendChild(o);});}
    opts($('sp'),DATA.species.map(s=>({v:s.id,t:s.name+' ('+s.element+')'})),true);
    const curSp=()=>byId($('sp').value);
    const curStage=()=>curSp().stages.find(s=>s.stage===$('stage').value);
    const curState=()=>$('state').value;
    const curVar=()=>curStage().states[curState()].find(v=>v.id===$('variant').value)||curStage().states[curState()][0];
    function refillStage(){opts($('stage'),curSp().stages.map(s=>s.stage));}
    function refillState(){opts($('state'),Object.keys(curStage().states));}
    function refillVariant(){opts($('variant'),curStage().states[curState()].map(v=>v.id));}
    refillStage();refillState();refillVariant();
    $('sp').onchange=()=>{refillStage();refillState();refillVariant();reset();};
    $('stage').onchange=()=>{refillState();refillVariant();reset();};
    $('state').onchange=()=>{refillVariant();reset();};
    $('variant').onchange=reset;
    $('play').onclick=()=>{playing=!playing;$('play').textContent=playing?'⏸ 暂停':'▶ 播放';};
    function reset(){t0=performance.now();}
    function lerp(a,b,u){return a+(b-a)*u;}
    function applyEase(m,u){switch(m){case 'linear':return u;case 'in':return u*u;case 'out':return 1-(1-u)*(1-u);case 'back':{const c1=1.70158,c3=c1+1;return 1+c3*Math.pow(u-1,3)+c1*Math.pow(u-1,2);}case 'elastic':{if(u<=0||u>=1)return u;const c4=2*Math.PI/3;return Math.pow(2,-10*u)*Math.sin((u*10-0.75)*c4)+1;}default:return u<.5?2*u*u:1-Math.pow(-2*u+2,2)/2;}}
    function phase(n){let s=0;for(let i=0;i<n.length;i++)s+=n.charCodeAt(i);return (s%100)/100*6.283;}
    function sway(n,t){if(n.indexOf('tail')>=0)return Math.sin(t*2+phase(n))*8;if(n.indexOf('leaf')>=0||n.indexOf('flame')>=0||n.indexOf('drop')>=0||n.indexOf('flower')>=0)return Math.sin(t*1.6+phase(n))*5;if(n.indexOf('ear')>=0||n.indexOf('arm')>=0)return Math.sin(t*2.4+phase(n))*3;return 0;}
    let gT=0;
    function sample(track,tau){if(!track||!track.length)return null;let a=track[0];for(let i=0;i<track.length;i++){if(track[i].t<=tau)a=track[i];else{const b=track[i],u=applyEase(a.ease||'inout',(tau-a.t)/Math.max(1e-4,b.t-a.t));return{dx:lerp(a.dx,b.dx,u),dy:lerp(a.dy,b.dy,u),sx:lerp(a.sx,b.sx,u),sy:lerp(a.sy,b.sy,u),rot:lerp(a.rot,b.rot,u),a:lerp(a.a,b.a,u)};}}return a;}
    function id0(kf){return kf?{dx:kf.dx,dy:kf.dy,sx:kf.sx,sy:kf.sy,rot:kf.rot,a:kf.a}:{dx:0,dy:0,sx:1,sy:1,rot:0,a:1};}
    function pseudo(n){return ((n*1103515245+12345)>>8)&0x7fff;}
    function drawPart(part,tr,pal,S){
      ctx.save();
      const rootPivotX=32*S,rootPivotY=58*S;
      ctx.translate(rootPivotX+tr.root.dx*S,rootPivotY+tr.root.dy*S);
      ctx.rotate(tr.root.rot*Math.PI/180);ctx.scale(tr.root.sx,tr.root.sy);ctx.translate(-rootPivotX,-rootPivotY);
      const lt=tr.local;const ax=(part.kind==='ellipse'?part.cx:(part.points.reduce((s,p)=>s+p[0],0)/part.points.length))*S;
      const ay=(part.kind==='ellipse'?part.cy:(part.points.reduce((s,p)=>s+p[1],0)/part.points.length))*S;
      ctx.translate(ax+lt.dx*S,ay+lt.dy*S);ctx.rotate((lt.rot+sway(part.name,gT))*Math.PI/180);ctx.scale(lt.sx,lt.sy);ctx.translate(-ax,-ay);
      ctx.globalAlpha=lt.a*tr.root.a;
      ctx.beginPath();
      if(part.kind==='ellipse'){ctx.ellipse(part.cx*S,part.cy*S,part.rx*S,part.ry*S,part.rot*Math.PI/180,0,7);}
      else{ctx.moveTo(part.points[0][0]*S,part.points[0][1]*S);part.points.slice(1).forEach(p=>ctx.lineTo(p[0]*S,p[1]*S));ctx.closePath();}
      if(pal[part.fill]){ctx.fillStyle=pal[part.fill];ctx.fill();}
      if(part.stroke&&part.strokeW>0){ctx.strokeStyle=pal[part.stroke];ctx.lineWidth=part.strokeW*S;ctx.lineJoin='round';ctx.stroke();}
      ctx.restore();
    }
    function drawParticles(v,tau,pal,S){
      const conf=['#ff6fb5','#ffd23c','#7be07b','#5fe0ff'];
      (v.emitters||[]).forEach((e,ei)=>{
        for(let i=0;i<e.count;i++){
          const spawn=e.t0+(e.t1-e.t0)*i/e.count;let age=tau-spawn;if(age<0||age>e.life)continue;
          const s=pseudo(ei*97+i*13),sp=((s%100)/100-0.5);
          const x=(e.x+e.vx*age+sp*6)*S, y=(e.y+e.vy*age+0.5*e.gravity*age*age+sp*4)*S;
          ctx.globalAlpha=Math.max(0,1-age/e.life);
          if(e.kind==='confetti'){ctx.fillStyle=conf[i%4];ctx.fillRect(x,y,e.size*S,e.size*S*1.6);}
          else{ctx.beginPath();const gr=e.kind==='bubble'?e.size*(1+age):e.size;ctx.arc(x,y,gr*S,0,7);ctx.fillStyle=(e.kind==='confetti')?conf[i%4]:(pal[e.color]||'#fff');ctx.fill();if(e.kind==='bubble'){ctx.strokeStyle='rgba(255,255,255,.6)';ctx.lineWidth=1;ctx.stroke();}}
        }
      });
      ctx.globalAlpha=1;
    }
    function frame(now){
      gT=now/1000;
      const v=curVar(),sp=curSp(),st=curStage(),S=cv.width/VB,speed=parseFloat($('speed').value);
      let el=(now-t0)/1000*speed;let tau=v.loop?(el%v.dur):Math.min(el,v.dur);const nt=tau/v.dur;
      ctx.clearRect(0,0,cv.width,cv.height);
      st.parts.forEach(part=>{
        const tr={root:id0(sample(v.root,nt)||v.root[0]),local:id0(sample(v.tracks[part.name],nt))};
        drawPart(part,tr,sp.palette,S);
      });
      drawParticles(v,tau,sp.palette,S);
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
    </script></body></html>
    """
}
