import SwiftUI

/// AI 原创小猫（程序化矢量）。皮肤随 level 切换（Lv1 灰猫 / Lv2 金猫），表情随 mood 变化。
/// MVP 实现，后续可替换为高保真 sprite 图集。
struct CatView: View {
    @ObservedObject var state: PetState

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(bgColor.opacity(0.15))
                    .frame(width: 132, height: 132)
                CatFace(mood: state.mood, fur: furColor, accent: accentColor)
                    .frame(width: 112, height: 112)
            }
            VStack(spacing: 3) {
                Text("Lv\(state.level) · \(moodText)")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityIdentifier("pet.state")
                    .accessibilityValue("\(moodRaw):\(state.level)")
                ProgressView(
                    value: min(state.energy, state.energyToNext),
                    total: max(state.energyToNext, 1)
                )
                .frame(width: 104)
                .tint(accentColor)
            }
        }
        .padding(10)
    }

    private var furColor: Color {
        state.level >= 2 ? Color(red: 0.98, green: 0.75, blue: 0.32) : Color(white: 0.62)
    }
    private var accentColor: Color {
        state.level >= 2 ? Color(red: 1.0, green: 0.55, blue: 0.1) : Color(white: 0.42)
    }
    private var bgColor: Color { state.level >= 2 ? .orange : .gray }

    private var moodText: String {
        switch state.mood {
        case .idle: return "发呆"
        case .working: return "干活中"
        case .waiting: return "等你"
        case .celebrate: return "完成啦"
        case .evolve: return "进化!"
        }
    }

    /// 机器可读的 mood 值（供 XCUITest 断言，避免依赖中文文案）。
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

/// 一张程序化的小猫脸。
struct CatFace: View {
    let mood: PetState.Mood
    let fur: Color
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // 耳朵
                Path { p in
                    p.move(to: CGPoint(x: w * 0.18, y: h * 0.32))
                    p.addLine(to: CGPoint(x: w * 0.30, y: h * 0.02))
                    p.addLine(to: CGPoint(x: w * 0.46, y: h * 0.26))
                    p.closeSubpath()
                    p.move(to: CGPoint(x: w * 0.82, y: h * 0.32))
                    p.addLine(to: CGPoint(x: w * 0.70, y: h * 0.02))
                    p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.26))
                    p.closeSubpath()
                }
                .fill(fur)

                // 头
                Ellipse()
                    .fill(fur)
                    .frame(width: w * 0.82, height: h * 0.72)
                    .position(x: w * 0.5, y: h * 0.56)

                // 眼睛（发呆时闭眼）
                eye(open: mood != .idle).position(x: w * 0.38, y: h * 0.52)
                eye(open: mood != .idle).position(x: w * 0.62, y: h * 0.52)

                // 鼻子
                Path { p in
                    p.move(to: CGPoint(x: w * 0.50, y: h * 0.60))
                    p.addLine(to: CGPoint(x: w * 0.47, y: h * 0.645))
                    p.addLine(to: CGPoint(x: w * 0.53, y: h * 0.645))
                    p.closeSubpath()
                }
                .fill(accent)

                // 胡须
                Path { p in
                    p.move(to: CGPoint(x: w * 0.32, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.58))
                    p.move(to: CGPoint(x: w * 0.32, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.70))
                    p.move(to: CGPoint(x: w * 0.68, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.58))
                    p.move(to: CGPoint(x: w * 0.68, y: h * 0.66))
                    p.addLine(to: CGPoint(x: w * 0.90, y: h * 0.70))
                }
                .stroke(Color.black.opacity(0.45), lineWidth: 1)

                if mood == .evolve || mood == .celebrate {
                    Text("✨")
                        .font(.system(size: w * 0.26))
                        .position(x: w * 0.84, y: h * 0.16)
                }
            }
        }
    }

    @ViewBuilder
    private func eye(open: Bool) -> some View {
        if open {
            Circle().fill(Color.black).frame(width: 12, height: 12)
        } else {
            Capsule().fill(Color.black).frame(width: 12, height: 3)
        }
    }
}
