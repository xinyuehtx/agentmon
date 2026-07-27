import Combine
import SwiftUI
import agentmonCore

/// 控制台的可观察数据源：AppDelegate 每次 pump 灌入快照，SwiftUI 视图响应刷新。
/// 动作通过闭包回传 AppDelegate（AppKit），保持 UI 与编排解耦。
final class AppModel: ObservableObject {
    // MARK: 仪表盘
    @Published var working = 0
    @Published var waiting = 0
    @Published var completed = 0
    @Published var activeClients = 0
    @Published var energy = 0.0
    @Published var level = 1
    @Published var energyToNext = 300.0
    @Published var isGraduated = false
    @Published var clients: [ClientSummary] = []
    @Published var sessions: [SessionRow] = []
    @Published var activity: [ActivityItem] = []
    @Published var lastEventAt: Date?
    @Published var eventsSeen = 0

    // MARK: 宠物
    @Published var displaySpecies = ""
    @Published var displayStage = ""
    @Published var isSkinMode = false
    @Published var graduated: [String] = []
    @Published var petVisible = true

    // MARK: 集成 + 配置
    @Published var integrations: [IntegrationRow] = []
    @Published var energyConfig: EnergyConfig = .default

    // MARK: 动作（由 AppDelegate 接线）
    var onToggleIntegration: ((String, Bool) -> Void)?
    var onSetPath: ((String, String) -> Void)?
    var onResetPath: ((String) -> Void)?
    var onSaveConfig: ((EnergyConfig) -> Void)?
    var onTogglePet: ((Bool) -> Void)?
    var onHatch: (() -> Void)?
    var onShowActive: (() -> Void)?
    var onShowSkin: ((String, String) -> Void)?
    var onRunDiagnostics: (() -> Void)?
    var onOpenLog: (() -> Void)?
}

/// 监控设置里一行集成的可编辑视图态。
struct IntegrationRow: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let mechanism: IntegrationMechanism
    var path: String
    var installed: Bool
    var error: String?
    let verified: Bool
    let note: String?
}
