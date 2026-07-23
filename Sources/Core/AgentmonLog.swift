import Foundation
import os

/// 轻量日志：`os.Logger`（Console.app / 统一日志）+ 可选文件镜像（用户可直接打开）。
///
/// 隐私：只记录事件元数据（kind/session/client/时间/计数），**绝不记录任务内容**。
/// 文件镜像仅在 `configure(fileURL:)` 后开启——App 启动时调用；测试默认不落文件，避免污染。
public final class AgentmonLog {
    public static let shared = AgentmonLog()

    private let queue = DispatchQueue(label: "com.agentmon.log")
    private var fileURL: URL?
    private let maxBytes: Int
    private let osLog = Logger(subsystem: "com.agentmon.app", category: "agentmon")

    public init(fileURL: URL? = nil, maxBytes: Int = 1_000_000) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
    }

    /// 开启文件镜像（未配置则只写 os.Logger）。
    public func configure(fileURL: URL) {
        queue.sync { self.fileURL = fileURL }
    }

    public func info(_ category: String, _ message: String) { emit("INFO", category, message) }
    public func warn(_ category: String, _ message: String) { emit("WARN", category, message) }
    public func error(_ category: String, _ message: String) { emit("ERROR", category, message) }

    /// 等待挂起的文件写入完成（测试用）。
    public func flush() { queue.sync {} }

    private func emit(_ level: String, _ category: String, _ message: String) {
        osLog.log(
            "[\(level, privacy: .public)] \(category, privacy: .public): \(message, privacy: .public)")
        queue.async { self.appendToFile(level, category, message) }
    }

    private func appendToFile(_ level: String, _ category: String, _ message: String) {
        guard let url = fileURL else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateIfNeeded(url)

        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "\(ts) [\(level)] \(category): \(message)\n"
        let data = Data(line.utf8)

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// 超过上限则把当前日志转存为 `.1`（保留单份备份，总量约 2×maxBytes）。
    private func rotateIfNeeded(_ url: URL) {
        let fm = FileManager.default
        guard
            let attrs = try? fm.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? Int, size >= maxBytes
        else { return }
        let backup = url.appendingPathExtension("1")
        try? fm.removeItem(at: backup)
        try? fm.moveItem(at: url, to: backup)
    }

    /// 读取日志尾部 n 行（诊断用）。
    public func recentLines(_ n: Int) -> [String] {
        queue.sync {}  // 确保挂起写入已落盘
        guard
            let url = fileURL,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(n))
    }
}
