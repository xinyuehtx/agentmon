import Foundation

/// 解析 `agentmon-hook` 的调用形态为一条 spool 事件的三要素。
/// 契约：`agentmon-hook <client> [<kind> [<sid>]]`
/// - 0 个额外参数：client 默认 "Claude Code"，从 stdin JSON 取 `hook_event_name`/`session_id`。
/// - 1 个额外参数（仅 client）：同样从 stdin 取（Claude 家族 + Codex，均为 Claude 同构 stdin）。
/// - 2~3 个额外参数（`client kind [sid]`）：直接用归一化 kind，不读 stdin（opencode 插件用，
///   避免 JS 里脆弱的 JSON 转义，也避免在 TTY 下阻塞读 stdin）。
/// 契约见 rfcs/multi-client-and-control-panel.md §4.3。
public struct HookInvocation: Equatable {
    public let eventName: String
    public let sessionID: String
    public let client: String

    public init(eventName: String, sessionID: String, client: String) {
        self.eventName = eventName
        self.sessionID = sessionID
        self.client = client
    }

    /// 是否需要读取 stdin（额外参数 < 2 时才需要）。main 据此避免在归一化模式下阻塞读 stdin。
    public static func needsStdin(arguments: [String]) -> Bool {
        arguments.dropFirst().count < 2
    }

    public static func resolve(arguments: [String], stdin: Data) -> HookInvocation {
        let extra = Array(arguments.dropFirst())  // 去掉程序名
        let client = extra.first ?? "Claude Code"

        if extra.count >= 2 {
            let kind = extra[1]
            let sid = extra.count >= 3 ? extra[2] : "unknown"
            return HookInvocation(eventName: kind, sessionID: sid, client: client)
        }

        let obj = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any]
        let eventName = (obj?["hook_event_name"] as? String) ?? "Unknown"
        let sessionID = (obj?["session_id"] as? String) ?? "unknown"
        return HookInvocation(eventName: eventName, sessionID: sessionID, client: client)
    }
}
