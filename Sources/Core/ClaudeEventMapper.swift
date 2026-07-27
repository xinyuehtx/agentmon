import Foundation

/// 各客户端 hook 事件名 → 标准任务事件。契约见 specs/agent-task-monitor.md §5.1、
/// rfcs/multi-client-and-control-panel.md §4.3。
public enum ClaudeEventMapper {
    public static func map(
        hookEventName: String,
        client: String,
        sessionID: String,
        timestamp: Date
    ) -> TaskEvent? {
        let kind: TaskEventKind
        switch hookEventName {
        // Claude 家族 hook 名 + opencode 插件归一化名 "start"
        case "UserPromptSubmit", "SubagentStart", "start": kind = .start
        // Notification（Claude/Qoder）、PermissionRequest（Codex）、opencode 归一化 "pause"
        case "Notification", "PermissionRequest", "pause": kind = .pause
        // Stop（Claude 家族/Codex）+ opencode 归一化 "end"
        case "Stop", "end": kind = .end
        // SubagentStop 有意忽略：会话结束以 Stop 计一次完成，避免重复计数
        default: return nil  // 其它 hook 事件不参与三态
        }
        return TaskEvent(client: client, sessionID: sessionID, kind: kind, timestamp: timestamp)
    }
}
