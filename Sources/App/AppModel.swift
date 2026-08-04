import AppKit
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
    @Published var growth = 1.0  // 0..1 幼年→成年
    @Published var displayLevel = 0  // Lv0..maxLevel
    @Published var unlockedActions: [String] = []  // 已解锁表现动作（中文名）
    @Published var nextUnlock: String?  // 下一级解锁的表现动作（中文名）；nil=已满级
    /// 成长形态（v3 多形态包）：形态 id 列表 + 当前形态；空=单形态包（aurora）。
    @Published var stages: [String] = []
    @Published var currentStage: String = ""
    /// 成长形态图鉴（含缩略图，供收藏 gallery）；面板打开时构建一次。
    @Published var forms: [PetFormInfo] = []
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
    @Published var diedElements: [String] = []  // 曾拥有但饿死（图鉴置灰）
    @Published var petVisible = true
    /// 全部 12 元素（图鉴）；`activeElement` 为当前活体宠物元素。
    @Published var elements: [PetElementInfo] = []
    @Published var activeElement = ""

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
    var onShowSkin: ((String) -> Void)?  // 展示某收藏元素
    var onSelectStage: ((String?) -> Void)?  // 满级固定成熟形态；nil=跟随成长
    var onRunDiagnostics: (() -> Void)?
    var onOpenLog: (() -> Void)?
}

/// 一个成长形态在图鉴 gallery 里的展示信息（缩略图取自该形态 idle 动画首帧）。
struct PetFormInfo: Identifiable {
    let id: String  // 形态 id（egg/baby/youth/mature…）
    let name: String  // 中文名
    let thumbnail: NSImage?
}

/// 一个元素在图鉴里的展示信息。
struct PetElementInfo: Identifiable {
    let id: String
    let name: String
    let tint: String  // 十六进制主题色
    let portraitPath: String  // 立绘绝对路径
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
