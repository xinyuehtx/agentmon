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
                if model.isSkinMode {
                    Text("展示：\(PetNaming.species(model.displaySpecies))（\(PetNaming.stage(model.displayStage))）")
                } else if model.isGraduated {
                    Text("Lv\(model.level)   已毕业 ✓ 可孵化新宠物")
                } else {
                    Text("Lv\(model.level)")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("桌宠设置").font(.title2).bold()

            CardSection(title: "显示") {
                Toggle(
                    "显示桌面宠物",
                    isOn: Binding(get: { model.petVisible }, set: { model.onTogglePet?($0) }))
            }

            CardSection(title: "宠物") {
                HStack {
                    Text(statusLine)
                    Spacer()
                    Button("孵化新宠物…") { model.onHatch?() }
                }
            }

            if !model.graduated.isEmpty {
                CardSection(title: "收藏皮肤（\(model.graduated.count)）") {
                    Button("显示当前宠物") { model.onShowActive?() }
                        .disabled(!model.isSkinMode)
                    Divider()
                    ForEach(model.graduated, id: \.self) { species in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(PetNaming.species(species)).font(.headline)
                            HStack {
                                ForEach(PetSelection.stageOrder, id: \.self) { stage in
                                    Button(PetNaming.stage(stage)) {
                                        model.onShowSkin?(species, stage)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        if model.isSkinMode {
            return "展示收藏：\(PetNaming.species(model.displaySpecies))（\(PetNaming.stage(model.displayStage))）"
        }
        if model.isGraduated { return "当前：\(PetNaming.species(model.displaySpecies)) · 已毕业 ✓" }
        return "当前：\(PetNaming.species(model.displaySpecies))（\(PetNaming.stage(model.displayStage))）"
    }
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

/// 物种 / 形态 id → 中文名（UI 展示；无映射则原样）。
enum PetNaming {
    static func species(_ id: String) -> String {
        ["bird_fire": "火焰鸟", "dog_cabbage": "白菜狗", "sealion_water": "水海狮"][id] ?? (id.isEmpty ? "宠物" : id)
    }
    static func stage(_ stage: String) -> String {
        ["egg": "幼年·蛋", "juvenile": "幼年体", "mature": "成熟体", "final": "成年体"][stage] ?? stage
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
