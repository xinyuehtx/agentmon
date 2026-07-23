import SwiftUI
import agentmonCore

/// 从 bundle / 环境变量 / 开发路径加载宠物图鉴。
enum PetAssets {
    static func load() -> PetCatalog? {
        if let url = Bundle.main.url(forResource: "pets", withExtension: "json"),
            let cat = try? PetLibrary.load(from: url)
        {
            return cat
        }
        if let path = ProcessInfo.processInfo.environment["AGENTMON_PETS"],
            let cat = try? PetLibrary.load(from: URL(fileURLWithPath: path))
        {
            return cat
        }
        if let exe = Bundle.main.executableURL {
            let dev = exe.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("assets/pets.json")
            if let cat = try? PetLibrary.load(from: dev) { return cat }
        }
        return nil
    }
}

/// 矢量宠物：SwiftUI Canvas 逐帧插值渲染部件 + 粒子（平滑卡通风，非像素）。
struct PetView: View {
    @ObservedObject var state: PetState
    let catalog: PetCatalog
    var onHide: () -> Void = {}

    var body: some View {
        VStack(spacing: 6) {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in render(ctx, size: size, at: timeline.date) }
                    .frame(width: 132, height: 132)
                    .accessibilityIdentifier("pet.canvas")
            }
            VStack(spacing: 3) {
                Text("Lv\(state.level) · \(moodText)")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityIdentifier("pet.state")
                    .accessibilityValue("\(moodRaw):\(state.level)")
                HStack(spacing: 12) {
                    Text("▶\(state.working)")
                    Text("⏸\(state.waiting)")
                    Text("✓\(state.completed)")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("pet.stats")
                .accessibilityValue("\(state.working):\(state.waiting):\(state.completed)")
            }
        }
        .padding(10)
        .contextMenu { Button("隐藏宠物", action: onHide) }
    }

    // MARK: - 渲染

    private func render(_ ctx: GraphicsContext, size: CGSize, at date: Date) {
        guard
            let species = catalog.species(id: state.species) ?? catalog.species.first,
            let stage = species.stage(state.stage) ?? species.stages.first
        else { return }
        let variant = state.variant ?? stage.states["idle"]?.first
        guard let v = variant else { return }

        let scale = size.width / stage.viewBox
        let elapsed = max(0, date.timeIntervalSince(state.variantStart))
        let tau = v.loop ? elapsed.truncatingRemainder(dividingBy: max(0.01, v.dur)) : min(elapsed, v.dur)
        let nt = max(0, min(1, tau / max(0.01, v.dur)))
        let rt = sample(v.root, nt)

        for part in stage.parts {
            let lt = sample(v.tracks[part.name] ?? [], nt)
            var c = ctx
            c.scaleBy(x: scale, y: scale)
            // root（绕底部中心）
            c.translateBy(x: 32 + rt.dx, y: 58 + rt.dy)
            c.rotate(by: .degrees(rt.rot))
            c.scaleBy(x: rt.sx, y: rt.sy)
            c.translateBy(x: -32, y: -58)
            // local（绕部件锚点）
            let (ax, ay) = anchor(part)
            c.translateBy(x: ax + lt.dx, y: ay + lt.dy)
            c.rotate(by: .degrees(lt.rot))
            c.scaleBy(x: lt.sx, y: lt.sy)
            c.translateBy(x: -ax, y: -ay)
            c.opacity = rt.a * lt.a

            let path = partPath(part)
            if let fill = Color(hex: species.palette[part.fill] ?? "") {
                c.fill(path, with: .color(fill))
            }
            if let key = part.stroke, part.strokeW > 0, let sc = Color(hex: species.palette[key] ?? "") {
                c.stroke(path, with: .color(sc), lineWidth: part.strokeW)
            }
        }
        drawParticles(ctx, v: v, tau: tau, scale: scale, palette: species.palette)
    }

    private func drawParticles(
        _ ctx: GraphicsContext, v: PetVariant, tau: Double, scale: CGFloat, palette: [String: String]
    ) {
        let conf = ["p", "y", "n", "b"]
        for (ei, e) in v.emitters.enumerated() {
            for i in 0..<e.count {
                let spawn = e.t0 + (e.t1 - e.t0) * Double(i) / Double(max(1, e.count))
                let age = tau - spawn
                if age < 0 || age > e.life { continue }
                let s = pseudo(ei * 97 + i * 13)
                let spread = Double(s % 100) / 100 - 0.5
                let x = e.x + e.vx * age + spread * 6
                let y = e.y + e.vy * age + 0.5 * e.gravity * age * age + spread * 4
                var c = ctx
                c.scaleBy(x: scale, y: scale)
                c.opacity = max(0, 1 - age / e.life)
                if e.kind == "confetti" {
                    let col = Color(hex: palette[conf[i % 4]] ?? "#ff6fb5") ?? .pink
                    c.fill(Path(CGRect(x: x, y: y, width: e.size, height: e.size * 1.6)), with: .color(col))
                } else {
                    let gr = e.kind == "bubble" ? e.size * (1 + age) : e.size
                    let col = Color(hex: palette[e.color] ?? "#ffffff") ?? .white
                    c.fill(
                        Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)), with: .color(col))
                }
            }
        }
    }

    // MARK: - 插值与几何

    private struct T {
        var dx = 0.0
        var dy = 0.0
        var sx = 1.0
        var sy = 1.0
        var rot = 0.0
        var a = 1.0
    }

    private func ease(_ u: Double) -> Double { u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2 }

    private func sample(_ track: [PetKeyframe], _ nt: Double) -> T {
        guard let first = track.first else { return T() }
        var a = first
        for kf in track {
            if kf.t <= nt {
                a = kf
            } else {
                let u = ease((nt - a.t) / max(1e-4, kf.t - a.t))
                return T(
                    dx: lerp(a.dx, kf.dx, u), dy: lerp(a.dy, kf.dy, u),
                    sx: lerp(a.sx, kf.sx, u), sy: lerp(a.sy, kf.sy, u),
                    rot: lerp(a.rot, kf.rot, u), a: lerp(a.a, kf.a, u))
            }
        }
        return T(dx: a.dx, dy: a.dy, sx: a.sx, sy: a.sy, rot: a.rot, a: a.a)
    }
    private func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
    private func pseudo(_ n: Int) -> Int { (n &* 1_103_515_245 &+ 12345) >> 8 & 0x7fff }

    private func anchor(_ part: PetPart) -> (Double, Double) {
        if part.kind == "ellipse" { return (part.cx, part.cy) }
        guard let pts = part.points, !pts.isEmpty else { return (part.cx, part.cy) }
        let sx = pts.reduce(0.0) { $0 + $1[0] }
        let sy = pts.reduce(0.0) { $0 + $1[1] }
        return (sx / Double(pts.count), sy / Double(pts.count))
    }

    private func partPath(_ part: PetPart) -> Path {
        if part.kind == "ellipse" {
            var path = Path(
                ellipseIn: CGRect(x: part.cx - part.rx, y: part.cy - part.ry, width: part.rx * 2, height: part.ry * 2))
            if part.rot != 0 {
                let t = CGAffineTransform(translationX: part.cx, y: part.cy)
                    .rotated(by: part.rot * .pi / 180).translatedBy(x: -part.cx, y: -part.cy)
                path = path.applying(t)
            }
            return path
        }
        var path = Path()
        if let pts = part.points, let head = pts.first {
            path.move(to: CGPoint(x: head[0], y: head[1]))
            for p in pts.dropFirst() { path.addLine(to: CGPoint(x: p[0], y: p[1])) }
            path.closeSubpath()
        }
        return path
    }

    private var moodText: String {
        switch state.mood {
        case .idle: return "发呆"
        case .working: return "干活中"
        case .waiting: return "等你"
        case .celebrate: return "完成啦"
        case .evolve: return "进化!"
        }
    }
    private var moodRaw: String {
        switch state.mood {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .celebrate: return "celebrate"
        case .evolve: return "evolve"
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255,
            blue: Double(v & 0xff) / 255)
    }
}
