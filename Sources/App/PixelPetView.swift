import AppKit
import SwiftUI
import agentmonCore

/// 从 bundle / 环境变量 / 开发路径加载宠物图鉴。
enum PetAssets {
    static func load() -> PetCatalog? {
        // 1. 打包 .app 的 Contents/Resources/pets.json
        if let url = Bundle.main.url(forResource: "pets", withExtension: "json"),
            let cat = try? PetLibrary.load(from: url)
        {
            return cat
        }
        // 2. 环境变量覆盖（开发/测试）
        if let path = ProcessInfo.processInfo.environment["AGENTMON_PETS"],
            let cat = try? PetLibrary.load(from: URL(fileURLWithPath: path))
        {
            return cat
        }
        // 3. 开发：可执行文件上溯到仓库 assets/pets.json（.build/debug/agentmon → repo/assets）
        if let exe = Bundle.main.executableURL {
            let dev = exe.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("assets/pets.json")
            if let cat = try? PetLibrary.load(from: dev) { return cat }
        }
        return nil
    }
}

/// 像素宠物：SwiftUI Canvas 逐帧渲染 assets/pets.json 的动画。
struct PixelPetView: View {
    @ObservedObject var state: PetState
    let catalog: PetCatalog
    var onHide: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation) { timeline in
                Canvas { ctx, size in
                    render(ctx, size: size, at: timeline.date)
                }
                .frame(width: 128, height: 128)
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

    private var animationKey: String {
        switch state.mood {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .celebrate, .evolve: return "complete"
        }
    }

    private func render(_ ctx: GraphicsContext, size: CGSize, at date: Date) {
        guard
            let species = catalog.species(id: state.species) ?? catalog.species.first,
            let stage = species.stage(state.stage) ?? species.stages.first,
            let anim = stage.anims[animationKey] ?? stage.anims["idle"],
            !anim.frames.isEmpty
        else { return }

        let count = anim.frames.count
        let tick = Int(date.timeIntervalSinceReferenceDate * Double(anim.fps))
        let index = anim.loop ? (tick % count) : min(tick % (count * 2), count - 1)
        let frame = anim.frames[index]

        let cols = frame.first?.count ?? 1
        let cell = size.width / CGFloat(cols)
        for (y, row) in frame.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                guard let hex = species.palette[String(ch)], let color = Color(hex: hex) else { continue }
                let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)
                ctx.fill(Path(rect), with: .color(color))
            }
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

extension Color {
    /// 从 "#rrggbb" 十六进制创建颜色。
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xff) / 255.0,
            green: Double((v >> 8) & 0xff) / 255.0,
            blue: Double(v & 0xff) / 255.0)
    }
}
