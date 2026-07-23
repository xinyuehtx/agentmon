import Foundation

/// Claude Code / Qoder hook 事件名 → 标准任务事件。契约见 specs/agent-task-monitor.md §5.1。
public enum ClaudeEventMapper {
    public static func map(
        hookEventName: String,
        client: String,
        sessionID: String,
        timestamp: Date
    ) -> TaskEvent? {
        let kind: TaskEventKind
        switch hookEventName {
        case "UserPromptSubmit", "SubagentStart": kind = .start
        case "Notification": kind = .pause
        case "Stop": kind = .end
        // SubagentStop 有意忽略：会话结束以 Stop 计一次完成，避免重复计数
        default: return nil  // 其它 hook 事件不参与三态
        }
        return TaskEvent(client: client, sessionID: sessionID, kind: kind, timestamp: timestamp)
    }
}
