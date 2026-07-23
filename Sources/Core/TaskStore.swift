import Foundation

/// 事件 → 每客户端三态计数。契约与状态机见 specs/agent-task-monitor.md §2。
///
/// 规则要点：
/// - 会话按 `client + sessionID` 命名空间隔离；
/// - 陈旧事件守卫：早于该会话已处理时间戳的事件整条忽略；
/// - `end` 幂等：仅当会话处于 working/waiting 时才计一次完成并回 idle。
public final class TaskStore {

    private enum SessionState { case working, waiting, idle }
    private struct Session {
        var state: SessionState
        var lastTS: Date
    }

    private var sessions: [String: Session] = [:]
    private var completedByClient: [String: Int] = [:]
    private var clientOrder: [String] = []

    public init() {}

    private func key(_ client: String, _ sid: String) -> String { client + "\u{1}" + sid }

    private func register(_ client: String) {
        if completedByClient[client] == nil {
            completedByClient[client] = 0
            clientOrder.append(client)
        }
    }

    public func apply(_ event: TaskEvent) {
        register(event.client)
        let k = key(event.client, event.sessionID)

        if let existing = sessions[k], event.timestamp < existing.lastTS {
            return  // 陈旧事件，忽略
        }

        var session = sessions[k] ?? Session(state: .idle, lastTS: event.timestamp)
        switch event.kind {
        case .start:
            session.state = .working
        case .pause:
            session.state = .waiting
        case .end:
            if session.state == .working || session.state == .waiting {
                completedByClient[event.client, default: 0] += 1
                session.state = .idle
            }
        // idle/未知会话的 end → 幂等 no-op
        }
        session.lastTS = event.timestamp
        sessions[k] = session
    }

    public func counts(for client: String) -> ClientCounts {
        let prefix = client + "\u{1}"
        var working = 0
        var waiting = 0
        for (k, s) in sessions where k.hasPrefix(prefix) {
            switch s.state {
            case .working: working += 1
            case .waiting: waiting += 1
            case .idle: break
            }
        }
        return ClientCounts(working: working, waiting: waiting, completed: completedByClient[client] ?? 0)
    }

    public func allClients() -> [String] { clientOrder }

    public var totalWorking: Int { sessions.values.lazy.filter { $0.state == .working }.count }
    public var totalWaiting: Int { sessions.values.lazy.filter { $0.state == .waiting }.count }
    public var totalCompleted: Int { completedByClient.values.reduce(0, +) }
}
