import Foundation

/// spool 目录事件摄取：读取 → 解析 → 映射为 TaskEvent，读入即删。
/// 契约见 specs/agent-task-monitor.md §5.3。
public final class SpoolIngestor {

    private let directory: URL
    private let fm = FileManager.default
    private let iso: ISO8601DateFormatter

    public init(directory: URL) {
        self.directory = directory
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        self.iso = formatter
    }

    private struct SpoolRecord: Decodable {
        let hookEventName: String
        let sessionID: String
        let client: String
        let receivedAt: String

        enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case client
            case receivedAt = "received_at"
        }
    }

    /// 读取目录内所有 `*.json`（忽略 `*.tmp`），解析→映射，按 timestamp 升序返回。
    /// 每个被读取的文件在返回前删除（无论是否解析成功）；解析失败者记录并跳过。
    public func drain() throws -> [TaskEvent] {
        guard fm.fileExists(atPath: directory.path) else { return [] }

        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var events: [TaskEvent] = []
        for file in files {
            defer { try? fm.removeItem(at: file) }  // 读入即删，损坏也删
            guard
                let data = try? Data(contentsOf: file),
                let record = try? JSONDecoder().decode(SpoolRecord.self, from: data),
                let ts = iso.date(from: record.receivedAt)
            else {
                AgentmonLog.shared.warn("spool", "跳过无法解析的文件 \(file.lastPathComponent)")
                continue  // 损坏/无法解析 → 跳过
            }
            if let event = ClaudeEventMapper.map(
                hookEventName: record.hookEventName,
                client: record.client,
                sessionID: record.sessionID,
                timestamp: ts
            ) {
                events.append(event)
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }
}
