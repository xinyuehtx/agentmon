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

    public init(ingestor: SpoolIngestor, engine: EnergyEngine) {
        self.ingestor = ingestor
        self.engine = engine
        self.engine.onEvolve = { [weak self] event in
            AgentmonLog.shared.info("evolve", "→ Lv\(event.newLevel)")
            self?.onEvolve?(event)
        }
    }

    @discardableResult
    public func pump(now: Date) -> MonitorSnapshot {
        let events = (try? ingestor.drain()) ?? []

        var completions = 0
        for event in events {
            let before = store.totalCompleted
            store.apply(event)
            let delta = store.totalCompleted - before
            completions += delta

            AgentmonLog.shared.info("event", "\(event.client)/\(event.sessionID) \(event.kind.rawValue)")
            if event.kind == .end && delta == 0 {
                AgentmonLog.shared.warn(
                    "event",
                    "Stop 落到未知/空闲会话 \(event.sessionID)（可能 App 重启导致，不计完成）")
            }
        }

        if !events.isEmpty {
            eventsSeen += events.count
            lastEventAt = events.map(\.timestamp).max()
            AgentmonLog.shared.info(
                "pump",
                "ingested=\(events.count) completions=\(completions) "
                    + "working=\(store.totalWorking) waiting=\(store.totalWaiting)")
        }

        if completions > 0 {
            engine.registerCompletions(completions, now: now)
        }
        engine.tick(now: now, workingCount: store.totalWorking, waitingCount: store.totalWaiting)
        return snapshot()
    }

    public func snapshot() -> MonitorSnapshot {
        let clients = store.allClients().map {
            ClientSummary(client: $0, counts: store.counts(for: $0))
        }
        return MonitorSnapshot(
            totalWorking: store.totalWorking,
            totalWaiting: store.totalWaiting,
            totalCompleted: store.totalCompleted,
            energy: engine.energy,
            level: engine.level,
            clients: clients,
            lastEventAt: lastEventAt,
            eventsSeen: eventsSeen
        )
    }

    public func persistentState(now: Date) -> PersistentState {
        var completed: [String: Int] = [:]
        for c in store.allClients() { completed[c] = store.counts(for: c).completed }
        return PersistentState(
            energy: engine.energy, level: engine.level,
            completedByClient: completed, lastTick: now)
    }
}
