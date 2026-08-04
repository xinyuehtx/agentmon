import Foundation

/// 某客户端的一行摘要（供 UI 展示）。
public struct ClientSummary: Equatable {
    public let client: String
    public let counts: ClientCounts
    public init(client: String, counts: ClientCounts) {
        self.client = client
        self.counts = counts
    }
}

/// 供 UI 消费的一次快照。
public struct MonitorSnapshot: Equatable {
    public let totalWorking: Int
    public let totalWaiting: Int
    public let totalCompleted: Int
    public let energy: Double
    public let level: Int
    public let clients: [ClientSummary]
    public let lastEventAt: Date?
    public let eventsSeen: Int
    /// 实际展示的物种（收藏皮肤模式为皮肤物种，否则为活跃宠物物种）。
    public let displaySpecies: String
    /// 实际展示的形态（皮肤模式为选定形态，否则由活跃 level 推导）。
    public let displayStage: String
    /// 是否处于收藏皮肤展示模式（成长已暂停）。
    public let isSkinMode: Bool
    /// 活跃宠物是否已毕业封顶。
    public let isGraduated: Bool
    /// 已解锁的永久皮肤物种列表。
    public let graduated: [String]
    /// 曾拥有但饿死的物种（图鉴置灰）。
    public let diedSpecies: [String]
}

/// 一条最近活动（用于控制台活动流）。契约见 rfcs/multi-client-and-control-panel.md §4.4。
public struct ActivityItem: Equatable {
    public let client: String
    public let sessionID: String
    public let kind: TaskEventKind
    public let at: Date

    public init(client: String, sessionID: String, kind: TaskEventKind, at: Date) {
        self.client = client
        self.sessionID = sessionID
        self.kind = kind
        self.at = at
    }
}

/// 编排：摄取 spool → 更新 TaskStore → 结算 EnergyEngine → 输出快照。
/// 时间由外部（App 的 Timer）通过 `pump(now:)` 驱动，保持 Core 可测。
public final class MonitorCoordinator {

    public let store = TaskStore()
    public let engine: EnergyEngine
    private let ingestor: SpoolIngestor
    public var onEvolve: ((EvolutionEvent) -> Void)?

    /// 最近一次摄取到事件的时间（事件的 received_at 中最大者）。
    public private(set) var lastEventAt: Date?
    /// 累计摄取的事件数。
    public private(set) var eventsSeen: Int = 0
    /// 当前完成计数所属的本地日期（跨天清零用）。
    private var completedDay: String = ""
    /// 本次安装分配到的宠物物种 id（App 设置，随状态持久化）。
    public var species: String?

    // MARK: - 生命周期

    /// 图集中全部可用物种 id（供挑选新物种）。
    public var availableSpecies: [String] = []
    /// 已毕业解锁的永久皮肤物种。
    public private(set) var graduated: [String] = []
    /// 曾拥有但饿死的物种（图鉴置灰用）；毕业后从此列移除。
    public private(set) var diedSpecies: [String] = []
    /// 当前展示的收藏皮肤物种；nil = 展示活跃宠物。
    public private(set) var displaySkin: String?
    /// 展示皮肤时选定的形态；nil = final。
    public private(set) var displayStage: String?
    /// 物种挑选器（可注入以便测试确定性）；默认用系统 RNG + PetSelection.nextSpecies。
    public var speciesPicker: (_ available: [String], _ graduated: [String], _ current: String?) -> String?
    /// 宠物毕业解锁永久皮肤时回调（参数为毕业物种）。
    public var onGraduate: ((String) -> Void)?
    /// 宠物饿死重生时回调（参数为死去的旧物种）。
    public var onDeath: ((String) -> Void)?

    private var pendingStarve = false

    /// 最近活动环形缓冲（最新在尾部），供控制台活动流。
    private var activityRing: [ActivityItem] = []
    private let activityCap = 200

    public init(ingestor: SpoolIngestor, engine: EnergyEngine) {
        self.ingestor = ingestor
        self.engine = engine
        self.speciesPicker = { available, graduated, current in
            var rng = SystemRandomNumberGenerator()
            return PetSelection.nextSpecies(
                available: available, graduated: graduated, current: current, using: &rng)
        }
        self.engine.onEvolve = { [weak self] event in
            AgentmonLog.shared.info("evolve", "→ Lv\(event.newLevel)")
            self?.onEvolve?(event)
        }
        self.engine.onGraduate = { [weak self] in self?.handleGraduate() }
        self.engine.onStarve = { [weak self] in self?.pendingStarve = true }
    }

    private func handleGraduate() {
        guard let species = species else { return }
        if !graduated.contains(species) { graduated.append(species) }
        diedSpecies.removeAll { $0 == species }  // 毕业即"复活"，从死亡列移除
        AgentmonLog.shared.info("pet", "毕业 → 解锁永久皮肤 \(species)")
        onGraduate?(species)
    }

    /// 恢复持久化的生命周期状态（毕业收藏 / 死亡记录 / 展示皮肤 / 当前物种）。
    public func restoreLifecycle(
        species: String?, graduated: [String], diedSpecies: [String] = [],
        displaySkin: String?, displayStage: String?
    ) {
        self.species = species
        self.graduated = graduated
        self.diedSpecies = diedSpecies.filter { !graduated.contains($0) }
        // 回填：活跃宠物已满级（可能在旧毕业规则下达成、当时未记录）却不在收藏内 →
        // 补记为已毕业，保证「满级即可切换/固定形态」且展示态可跨重启持久化。
        if let s = species, engine.isGraduated, !self.graduated.contains(s) {
            self.graduated.append(s)
        }
        // 展示皮肤仅在物种确实已毕业时才生效，否则回落活跃宠物。
        if let skin = displaySkin, self.graduated.contains(skin) {
            self.displaySkin = skin
            self.displayStage = displayStage
        } else {
            self.displaySkin = nil
            self.displayStage = nil
        }
    }

    /// 主动孵化新宠物：挑新物种、重置活跃宠物、切回活跃展示。
    public func hatchNewPet(now: Date) {
        let old = species
        let pick = speciesPicker(availableSpecies, graduated, old) ?? old ?? availableSpecies.first
        species = pick
        displaySkin = nil
        displayStage = nil
        engine.rebirth(now: now)
        AgentmonLog.shared.info("pet", "孵化新宠物 \(old ?? "?") → \(pick ?? "?")")
    }

    /// 切换到展示某收藏皮肤（成长暂停）。仅接受已毕业物种。
    public func showSkin(_ species: String, stage: String?) {
        guard graduated.contains(species) else { return }
        displaySkin = species
        displayStage = stage
    }

    /// 切回展示活跃宠物（恢复成长）。
    public func showActivePet() {
        displaySkin = nil
        displayStage = nil
    }

    /// 将当前活跃宠物固定为指定成长/成熟形态展示；`stage == nil` 取消固定、跟随成长。
    /// 仅在活跃宠物已毕业（满级）时生效——复用皮肤展示通道，故成长暂停、能量永久冻结。
    /// 返回是否生效（未满级或无活跃物种时忽略）。
    @discardableResult
    public func pinDisplayStage(_ stage: String?) -> Bool {
        // 活跃宠物满级即可固定/切换形态；不再要求已在 graduated 收藏内（旧状态可能未记录）。
        guard let species = species, engine.isGraduated else { return false }
        if let stage = stage {
            displaySkin = species
            displayStage = stage
        } else {
            displaySkin = nil
            displayStage = nil
        }
        return true
    }

    /// 本地日期字符串（YYYY-MM-DD），由入参 `date` + 系统时区决定，保持可测。
    public static func dayString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 启动时回填持久化的完成计数：同一天则恢复，跨天则从 0 开始。
    public func restore(completedByClient: [String: Int], day: String?, now: Date) {
        let today = Self.dayString(now)
        if let day = day, day == today {
            store.seedCompleted(completedByClient)
        }
        completedDay = today
    }

    @discardableResult
    public func pump(now: Date) -> MonitorSnapshot {
        // 跨天：完成计数清零
        let today = Self.dayString(now)
        if today != completedDay {
            if !completedDay.isEmpty { store.resetCompleted() }
            completedDay = today
            AgentmonLog.shared.info("day", "进入新的一天 \(today)，完成计数清零")
        }

        let events = (try? ingestor.drain()) ?? []

        var completions = 0
        for event in events {
            let before = store.totalCompleted
            store.apply(event)
            let delta = store.totalCompleted - before
            completions += delta

            AgentmonLog.shared.info("event", "\(event.client)/\(event.sessionID) \(event.kind.rawValue)")
            activityRing.append(
                ActivityItem(
                    client: event.client, sessionID: event.sessionID, kind: event.kind,
                    at: event.timestamp))
            if event.kind == .end && delta == 0 {
                AgentmonLog.shared.warn(
                    "event",
                    "Stop 落到未知/空闲会话 \(event.sessionID)（可能 App 重启导致，不计完成）")
            }
        }

        if !events.isEmpty {
            eventsSeen += events.count
            lastEventAt = events.map(\.timestamp).max()
            if activityRing.count > activityCap {
                activityRing.removeFirst(activityRing.count - activityCap)
            }
            AgentmonLog.shared.info(
                "pump",
                "ingested=\(events.count) completions=\(completions) "
                    + "working=\(store.totalWorking) waiting=\(store.totalWaiting)")
        }

        // 展示收藏皮肤期间暂停活跃宠物成长（只推进 lastTick，不结算能量/饥饿）。
        if displaySkin != nil {
            engine.suspend(now: now)
        } else {
            if completions > 0 {
                engine.registerCompletions(completions, now: now)
            }
            engine.tick(now: now, workingCount: store.totalWorking, waitingCount: store.totalWaiting)
        }

        // 饿死重生：能量长期归零空闲 → 换新蛋。
        if pendingStarve {
            pendingStarve = false
            let old = species
            if let old = old, !graduated.contains(old), !diedSpecies.contains(old) {
                diedSpecies.append(old)  // 记录死亡（图鉴置灰）
            }
            hatchNewPet(now: now)
            AgentmonLog.shared.info("pet", "饿死重生 \(old ?? "?") → \(species ?? "?")")
            onDeath?(old ?? "")
        }
        return snapshot()
    }

    /// 最近活动（最新在前），最多 `limit` 条。供控制台活动流。
    public func recentActivity(limit: Int) -> [ActivityItem] {
        Array(activityRing.suffix(max(0, limit)).reversed())
    }

    public func snapshot() -> MonitorSnapshot {
        let clients = store.allClients().map {
            ClientSummary(client: $0, counts: store.counts(for: $0))
        }
        let activeSpecies = species ?? ""
        let isSkinMode = displaySkin != nil
        let shownSpecies = displaySkin ?? activeSpecies
        let shownStage =
            isSkinMode ? (displayStage ?? "final") : PetSelection.stage(forLevel: engine.level)
        return MonitorSnapshot(
            totalWorking: store.totalWorking,
            totalWaiting: store.totalWaiting,
            totalCompleted: store.totalCompleted,
            energy: engine.energy,
            level: engine.level,
            clients: clients,
            lastEventAt: lastEventAt,
            eventsSeen: eventsSeen,
            displaySpecies: shownSpecies,
            displayStage: shownStage,
            isSkinMode: isSkinMode,
            isGraduated: engine.isGraduated,
            graduated: graduated,
            diedSpecies: diedSpecies
        )
    }

    public func persistentState(now: Date) -> PersistentState {
        var completed: [String: Int] = [:]
        for c in store.allClients() { completed[c] = store.counts(for: c).completed }
        return PersistentState(
            energy: engine.energy, level: engine.level,
            completedByClient: completed, lastTick: now,
            completedDay: completedDay.isEmpty ? Self.dayString(now) : completedDay,
            species: species,
            starveMinutes: engine.starveMinutes,
            graduated: graduated,
            displaySkin: displaySkin,
            displayStage: displayStage,
            diedSpecies: diedSpecies)
    }
}
