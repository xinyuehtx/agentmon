import Foundation

/// 原子写入一个 spool 事件文件（temp + rename）。由 `agentmon-hook` 与 App 复用。
/// 契约见 specs/agent-task-monitor.md §5.2。
public enum SpoolWriter {
    public static func write(
        hookEventName: String,
        sessionID: String,
        client: String,
        receivedAt: Date,
        directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let payload: [String: String] = [
            "hook_event_name": hookEventName,
            "session_id": sessionID,
            "client": client,
            "received_at": iso.string(from: receivedAt),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let id = UUID().uuidString
        let tmp = directory.appendingPathComponent("\(id).json.tmp")
        let final = directory.appendingPathComponent("\(id).json")
        try data.write(to: tmp)
        try FileManager.default.moveItem(at: tmp, to: final)
    }
}
