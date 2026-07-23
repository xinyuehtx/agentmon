import AppKit
import ImageIO
import SwiftUI
import agentmonCore

/// 加载光栅图集清单并按需把「条」PNG 切片为逐帧 CGImage（缓存）。
final class RasterPetStore {
    let manifest: RasterManifest
    let baseDir: URL
    private var cache: [String: [CGImage]] = [:]

    init(manifest: RasterManifest, baseDir: URL) {
        self.manifest = manifest
        self.baseDir = baseDir
    }

    static func load() -> RasterPetStore? {
        func store(_ url: URL) -> RasterPetStore? {
            guard let m = try? RasterLibrary.load(from: url) else { return nil }
            return RasterPetStore(manifest: m, baseDir: url.deletingLastPathComponent())
        }
        if let url = Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "pets_raster"),
            let s = store(url)
        {
            return s
        }
        if let path = ProcessInfo.processInfo.environment["AGENTMON_PETS_RASTER"],
            let s = store(URL(fileURLWithPath: path))
        {
            return s
        }
        if let exe = Bundle.main.executableURL {
            let dev = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("assets/pets_raster/manifest.json")
            if let s = store(dev) { return s }
        }
        return nil
    }

    func frames(_ action: RasterAction) -> [CGImage] {
        if let cached = cache[action.file] { return cached }
        var out: [CGImage] = []
        let url = baseDir.appendingPathComponent(action.file)
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
        {
            let fw = img.width / max(1, action.frames)
            for i in 0..<action.frames {
                if let f = img.cropping(to: CGRect(x: i * fw, y: 0, width: fw, height: img.height)) { out.append(f) }
            }
        }
        cache[action.file] = out
        return out
    }
}

/// 光栅宠物：播放用户原创图集的逐帧动画（透明、抗锯齿缩放）。
struct RasterPetView: View {
    @ObservedObject var state: PetState
    let store: RasterPetStore
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

    private func render(_ ctx: GraphicsContext, size: CGSize, at date: Date) {
        let m = store.manifest
        guard
            let species = m.species(id: state.species) ?? m.species.first,
            let stage = species.stage(state.stage) ?? species.stages.first
        else { return }
        let key = actionKey(state.mood)
        guard let action = stage.actions[key] ?? stage.actions["idle"] ?? stage.actions.values.first else { return }
        let frames = store.frames(action)
        guard !frames.isEmpty else { return }

        let n = frames.count
        let loop = key != "complete"
        let elapsed = max(0, date.timeIntervalSince(state.variantStart))
        let cycle = Double(n) / Double(max(1, action.fps))  // 一轮秒数
        // 连续帧位置（用于交叉溶解补帧，播放更顺滑）
        let u: Double =
            loop
            ? (elapsed.truncatingRemainder(dividingBy: cycle) / cycle) * Double(n)
            : min(elapsed / cycle, 0.999) * Double(max(1, n - 1))
        let i = min(Int(u), n - 1)
        let nextI = loop ? (i + 1) % n : min(i + 1, n - 1)
        let f = u - Double(Int(u))

        // 帧尺寸一致（并集裁剪），同位绘制 → 交叉溶解即平滑补帧
        func draw(_ cg: CGImage, opacity: Double) {
            let iw = CGFloat(cg.width)
            let ih = CGFloat(cg.height)
            let scale = min(size.width / iw, size.height / ih)
            let w = iw * scale
            let h = ih * scale
            var c = ctx
            c.opacity = opacity
            c.draw(
                Image(decorative: cg, scale: 1),
                in: CGRect(x: (size.width - w) / 2, y: size.height - h, width: w, height: h))
        }
        draw(frames[i], opacity: 1)
        if f > 0.001 { draw(frames[nextI], opacity: f) }
    }

    private func actionKey(_ mood: PetState.Mood) -> String {
        switch mood {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .celebrate, .evolve: return "complete"
        }
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
