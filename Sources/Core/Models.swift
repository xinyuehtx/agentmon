import Foundation

/// 任务事件类型。契约见 specs/agent-task-monitor.md §1。
public enum TaskEventKind: String, Codable, Equatable {
    case start  // 任务启动 / 从等待恢复 → working
    case pause  // 等待用户输入/授权 → waiting
    case end  // 任务回合结束 → completed，会话回 idle
}

/// 一条标准化任务事件。
public struct TaskEvent: Equatable {
    public let client: String
    public let sessionID: String
    public let kind: TaskEventKind
    public let timestamp: Date

    public init(client: String, sessionID: String, kind: TaskEventKind, timestamp: Date) {
        self.client = client
        self.sessionID = sessionID
        self.kind = kind
        self.timestamp = timestamp
    }
}

/// 某客户端的三态计数（working/waiting 为当前活跃会话数，completed 为累计）。
public struct ClientCounts: Equatable {
    public var working: Int
    public var waiting: Int
    public var completed: Int

    public init(working: Int, waiting: Int, completed: Int) {
        self.working = working
        self.waiting = waiting
        self.completed = completed
    }
}

/// 进化事件（升到 newLevel）。
public struct EvolutionEvent: Equatable {
    public let newLevel: Int
    public init(newLevel: Int) { self.newLevel = newLevel }
}
