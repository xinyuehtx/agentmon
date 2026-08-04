import AppKit
import SwiftUI
import agentmonCore

/// 控制台主视图：侧栏三段（仪表盘 / 监控设置 / 桌宠设置），暗色主题，读 `AppModel` 实时刷新。
/// 契约见 rfcs/multi-client-and-control-panel.md §4.6。
struct ControlPanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: Section? = .dashboard

    enum Section: String, CaseIterable, Identifiable {
        case dashboard = "仪表盘"
        case monitor = "监控设置"
        case pet = "桌宠设置"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .dashboard: return "chart.bar.doc.horizontal"
            case .monitor: return "slider.horizontal.3"
            case .pet: return "pawprint.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.rawValue, systemImage: s.symbol).tag(s)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            ScrollView {
                switch section ?? .dashboard {
                case .dashboard: DashboardView()
                case .monitor: MonitorSettingsView()
                case .pet: PetSettingsView()
                }
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .preferredColorScheme(.dark)
    }
}

// MARK: - 仪表盘

private struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("仪表盘").font(.title2).bold()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                StatCard(title: "工作中", value: "\(model.working)", color: .green, symbol: "play.fill")
                StatCard(title: "等待中", value: "\(model.waiting)", color: .orange, symbol: "pause.fill")
                StatCard(title: "已完成", value: "\(model.completed)", color: .blue, symbol: "checkmark")
                StatCard(
                    title: "活跃客户端", value: "\(model.activeClients)", color: .purple, symbol: "person.2.fill")
            }

            energyCard

            if !model.clients.isEmpty {
                CardSection(title: "各客户端") {
                    ForEach(model.clients, id: \.client) { c in
                        HStack {
                            Text(c.client).font(.callout)
                            Spacer()
                            Text("▶\(c.counts.working)  ⏸\(c.counts.waiting)  ✓\(c.counts.completed)")
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            kanban
            activityFeed
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var energyCard: some View {
        CardSection(title: model.isSkinMode ? "宠物（展示收藏 · 成长已暂停）" : "宠物") {
            HStack {
                let cap = PetProgression.maxLevel
                let form = model.stages.isEmpty ? "" : " · \(PetProgression.stageName(model.currentStage))"
                if model.isSkinMode {
                    if model.stages.isEmpty {
                        Text("展示：\(PetNaming.species(model.displaySpecies))")
                    } else {
                        Text("固定形态：\(PetProgression.stageName(model.currentStage))")
                    }
                } else if model.isGraduated {
                    Text("Lv\(model.displayLevel)/\(cap)\(form)   已满级 ✓")
                } else {
                    Text("Lv\(model.displayLevel)/\(cap)\(form)")
                    ProgressView(value: min(model.energy, model.energyToNext), total: max(1, model.energyToNext))
                        .frame(maxWidth: 240)
                    Text("\(Int(model.energy))/\(Int(model.energyToNext))")
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var kanban: some View {
        CardSection(title: "会话看板") {
            HStack(alignment: .top, spacing: 12) {
                KanbanColumn(title: "工作中", color: .green, rows: rows(state: "working"))
                KanbanColumn(title: "等待中", color: .orange, rows: rows(state: "waiting"))
                KanbanColumn(title: "空闲", color: .gray, rows: rows(state: "idle"))
            }
        }
    }

    private func rows(state: String) -> [SessionRow] {
        model.sessions.filter { $0.state == state }
    }

    private var activityFeed: some View {
        CardSection(title: "活动流") {
            if model.activity.isEmpty {
                Text("暂无事件 —— 启用集成并在客户端新开会话后跑任务。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.activity.prefix(30).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 8) {
                        KindBadge(kind: item.kind)
                        Text(item.client).font(.callout)
                        Text(String(item.sessionID.prefix(8)))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Text(TimeFmt.ago(item.at)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 监控设置

private struct MonitorSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("监控设置").font(.title2).bold()

            CardSection(title: "客户端集成") {
                ForEach(model.integrations) { row in
                    IntegrationSettingsRow(row: row)
                    if row.id != model.integrations.last?.id { Divider() }
                }
            }

            HStack {
                Button("运行诊断…") { model.onRunDiagnostics?() }
                Button("打开日志文件") { model.onOpenLog?() }
            }

            EnergyConfigEditor()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IntegrationSettingsRow: View {
    @EnvironmentObject var model: AppModel
    let row: IntegrationRow
    @State private var path: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(row.name, systemImage: row.symbol).font(.headline)
                if !row.verified { Badge(text: "未验证", color: .orange) }
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { row.installed },
                        set: { model.onToggleIntegration?(row.id, $0) })
                )
                .labelsHidden()
            }
            if let note = row.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("配置路径", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .onSubmit { model.onSetPath?(row.id, path) }
                Button("重置") {
                    model.onResetPath?(row.id)
                }
            }
            if let error = row.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .onAppear { path = row.path }
        .onChange(of: row.path) { path = $0 }
    }
}

private struct EnergyConfigEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var working = 2.0
    @State private var waiting = -1.0
    @State private var bonus = 30.0
    @State private var idle = -0.5
    @State private var gradLevel = 5.0

    var body: some View {
        CardSection(title: "能量参数") {
            numberRow("工作中 / 分钟", $working)
            numberRow("等待中 / 分钟", $waiting)
            numberRow("完成加成（一次性）", $bonus)
            numberRow("空闲衰减 / 分钟", $idle)
            numberRow("毕业封顶等级", $gradLevel)
            HStack {
                Spacer()
                Button("保存参数") {
                    var c = model.energyConfig
                    c.workingPerMin = working
                    c.waitingPerMin = waiting
                    c.completedBonus = bonus
                    c.idleDecayPerMin = idle
                    c.graduationLevel = Int(gradLevel)
                    model.onSaveConfig?(c)
                }
            }
        }
        .onAppear { syncFromModel() }
        .onChange(of: model.energyConfig) { _ in syncFromModel() }
    }

    private func syncFromModel() {
        let c = model.energyConfig
        working = c.workingPerMin
        waiting = c.waitingPerMin
        bonus = c.completedBonus
        idle = c.idleDecayPerMin
        gradLevel = Double(c.graduationLevel)
    }

    private func numberRow(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            TextField("", value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 100)
            Spacer()
        }
    }
}

// MARK: - 桌宠设置

private struct PetSettingsView: View {
    @EnvironmentObject var model: AppModel

    private var unlocked: Set<String> {
        Set(model.graduated + [model.activeElement])
    }

    private func cellState(_ id: String) -> ElementCellState {
        if unlocked.contains(id) { return .owned }
        if model.diedElements.contains(id) { return .dead }
        return .unowned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("桌宠设置").font(.title2).bold()

            CardSection(title: "显示") {
                Toggle(
                    "显示桌面宠物",
                    isOn: Binding(get: { model.petVisible }, set: { model.onTogglePet?($0) }))
            }

            CardSection(title: "宠物状态") {
                HStack {
                    Text(statusLine)
                    Spacer()
                    if model.elements.isEmpty {
                        // 多形态包（verdant）：无元素/收藏机制
                    } else if model.isSkinMode {
                        Button("显示当前宠物") { model.onShowActive?() }
                    }
                    if !model.elements.isEmpty {
                        Button("孵化新宠物…") { model.onHatch?() }
                    }
                }
                Text(
                    model.unlockedActions.isEmpty
                        ? "随机动作：暂无（升级解锁；核心反应始终可用）"
                        : "随机动作：" + model.unlockedActions.joined(separator: "、")
                )
                .font(.caption).foregroundStyle(.secondary)
                if let next = model.nextUnlock {
                    Text("下一级解锁：\(next)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("已满级：全部动作解锁").font(.caption).foregroundStyle(.secondary)
                }
            }

            if !model.stages.isEmpty {
                // 多形态包（verdant）：成长形态进度；满级后可固定任意成熟形态展示
                CardSection(title: "成长形态") {
                    Text(
                        model.isGraduated
                            ? "已满级：点选任一形态固定展示，能量永久冻结、不再消耗或增长。"
                            : "随等级进化：升级即变为下一形态。满级后可固定成熟形态。"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(Array(model.stages.enumerated()), id: \.offset) { idx, st in
                            let isCur = st == model.currentStage
                            let reached = idx <= (model.stages.firstIndex(of: model.currentStage) ?? 0)
                            HStack(spacing: 4) {
                                Text(PetProgression.stageName(st))
                                    .font(.caption).bold(isCur)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(
                                            isCur
                                                ? Color.green.opacity(0.3)
                                                : Color.primary.opacity(reached ? 0.1 : 0.04))
                                    )
                                    .foregroundStyle(reached ? .primary : .secondary)
                                    .contentShape(Capsule())
                                    .onTapGesture {
                                        if model.isGraduated { model.onSelectStage?(st) }
                                    }
                                    .help(model.isGraduated ? "固定为「\(PetProgression.stageName(st))」形态" : "")
                                if idx < model.stages.count - 1 {
                                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if model.isGraduated {
                        HStack {
                            if model.isSkinMode {
                                Text("已固定：\(PetProgression.stageName(model.currentStage))")
                                    .font(.caption).foregroundStyle(.green)
                            }
                            Spacer()
                            Button("恢复默认（成熟）") { model.onSelectStage?(nil) }
                                .disabled(!model.isSkinMode)
                        }
                    }
                }
            } else if !model.elements.isEmpty {
                // 单形态元素包（aurora）：元素图鉴收藏
                CardSection(title: "元素图鉴（\(unlocked.count)/\(model.elements.count)）") {
                    Text("完成任务养成、毕业即解锁新元素；点击已解锁元素切换展示。")
                        .font(.caption).foregroundStyle(.secondary)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10
                    ) {
                        ForEach(model.elements) { e in
                            ElementCell(
                                element: e,
                                state: cellState(e.id),
                                isCurrent: e.id == model.displaySpecies,
                                onTap: {
                                    if e.id == model.activeElement {
                                        model.onShowActive?()
                                    } else {
                                        model.onShowSkin?(e.id)
                                    }
                                })
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        let max = PetProgression.maxLevel
        if !model.stages.isEmpty {
            // 多形态包（verdant）：等级=形态
            let form = PetProgression.stageName(model.currentStage)
            let cap = model.isGraduated ? " · 已成熟 ✓" : ""
            return "Lv\(model.displayLevel)/\(max) · \(form)\(cap)"
        }
        let name = PetNaming.species(model.displaySpecies)
        if model.isSkinMode { return "展示收藏：\(name)" }
        if model.isGraduated { return "当前：\(name) · Lv\(model.displayLevel)/\(max) · 满级 ✓" }
        return "当前：\(name) · Lv\(model.displayLevel)/\(max) · \(growthStage)"
    }

    private var growthStage: String {
        if model.growth >= 0.98 { return "成年" }
        if model.growth >= 0.75 { return "成长中" }
        return "幼年"
    }
}

/// 图鉴单元格三态：已拥有(可点切换) / 已饿死(置灰) / 未拥有(? 占位)。
private enum ElementCellState { case owned, dead, unowned }

/// 图鉴单元格：立绘缩略 + 名称，按三态渲染。
private struct ElementCell: View {
    let element: PetElementInfo
    let state: ElementCellState
    let isCurrent: Bool
    let onTap: () -> Void

    private var owned: Bool { state == .owned }

    var body: some View {
        VStack(spacing: 4) {
            portrait
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(owned ? Color(white: 0.92) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(borderColor, lineWidth: isCurrent ? 2.5 : 1))
            Text(label).font(.caption2).foregroundStyle(owned ? .primary : .secondary)
        }
        .opacity(owned ? 1 : (state == .dead ? 0.5 : 0.4))
        .contentShape(Rectangle())
        .onTapGesture { if owned { onTap() } }
        .help(helpText)
    }

    @ViewBuilder private var portrait: some View {
        switch state {
        case .owned:
            if let img = NSImage(contentsOfFile: element.portraitPath) {
                Image(nsImage: img).resizable().scaledToFit().padding(4)
            } else {
                Image(systemName: "pawprint.fill").foregroundStyle(tintColor)
            }
        case .dead:
            if let img = NSImage(contentsOfFile: element.portraitPath) {
                Image(nsImage: img).resizable().scaledToFit().padding(4).saturation(0).opacity(0.55)
            } else {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
        case .unowned:
            Image(systemName: "questionmark").font(.title2).foregroundStyle(.secondary)
        }
    }

    private var borderColor: Color {
        switch state {
        case .owned: return isCurrent ? tintColor : tintColor.opacity(0.35)
        case .dead: return Color.gray.opacity(0.4)
        case .unowned: return Color.gray.opacity(0.25)
        }
    }
    private var label: String {
        switch state {
        case .owned: return element.name
        case .dead: return element.name + "·亡"
        case .unowned: return "？"
        }
    }
    private var helpText: String {
        switch state {
        case .owned: return element.name
        case .dead: return "\(element.name)（已饿死）"
        case .unowned: return "未拥有"
        }
    }
    private var tintColor: Color { Color(hex: element.tint) ?? .accentColor }
}

// MARK: - 复用小组件

private struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12)))
    }
}

private struct CardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
        }
    }
}

private struct KanbanColumn: View {
    let title: String
    let color: Color
    let rows: [SessionRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(title)（\(rows.count)）").font(.subheadline).bold()
            }
            if rows.isEmpty {
                Text("—").foregroundStyle(.secondary).font(.caption)
            } else {
                ForEach(Array(rows.prefix(8).enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.client).font(.caption).bold()
                        Text(String(r.sessionID.prefix(8))).font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KindBadge: View {
    let kind: TaskEventKind
    var body: some View {
        Text(text).font(.caption2).bold().padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.25))).foregroundStyle(color)
    }
    private var text: String {
        switch kind {
        case .start: return "开始"
        case .pause: return "等待"
        case .end: return "完成"
        }
    }
    private var color: Color {
        switch kind {
        case .start: return .green
        case .pause: return .orange
        case .end: return .blue
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.25))).foregroundStyle(color)
    }
}

/// 元素 id → 中文名（UI 展示；无映射则原样）。
enum PetNaming {
    private static let names: [String: String] = [
        "water": "水", "grass": "草", "fire": "火", "wind": "风",
        "electric": "电", "ice": "冰", "ghost": "幽灵", "psychic": "超能",
        "rock": "岩石", "light": "光", "dark": "暗", "rainbow": "彩虹",
    ]
    static func species(_ id: String) -> String {
        names[id] ?? (id.isEmpty ? "极光罗盘猫" : id)
    }
}

extension Color {
    /// 从 "#RRGGBB" 十六进制创建颜色。
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255)
    }
}

private enum TimeFmt {
    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(max(0, s)) 秒前" }
        if s < 3600 { return "\(s / 60) 分钟前" }
        return "\(s / 3600) 小时前"
    }
}
