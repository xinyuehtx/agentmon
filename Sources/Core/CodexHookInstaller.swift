import Foundation

/// 向 Codex 的 `~/.codex/config.toml` 追加/移除 agentmon hooks（TOML 标记块）。
/// 不引 TOML 解析依赖：用 `# >>> agentmon >>>` / `# <<< agentmon <<<` 包裹一段合法的
/// array-of-tables，追加在文件末尾（EOF 追加 `[[hooks.X]]` 对 TOML 合法、幂等且可精确回滚）。
/// Codex command hook 从 stdin 收 `hook_event_name`+`session_id`（与 Claude 同构），故上报器复用 stdin 路径。
/// 契约见 rfcs/multi-client-and-control-panel.md §4.2。
public final class CodexHookInstaller: IntegrationInstaller {

    static let startMarker = "# >>> agentmon (managed; do not edit) >>>"
    static let endMarker = "# <<< agentmon <<<"

    private let configURL: URL
    private let reporterCommand: String
    private let events: [String]
    private let fm = FileManager.default

    public init(configURL: URL, reporterCommand: String, events: [String]) {
        self.configURL = configURL
        self.reporterCommand = reporterCommand
        self.events = events
    }

    private var backupURL: URL {
        configURL.deletingLastPathComponent()
            .appendingPathComponent(configURL.lastPathComponent + ".agentmon.bak")
    }

    private func readText() -> String {
        guard let data = try? Data(contentsOf: configURL) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private func writeText(_ text: String) throws {
        try fm.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = configURL.appendingPathExtension("tmp")
        try Data(text.utf8).write(to: tmp)
        if fm.fileExists(atPath: configURL.path) { try fm.removeItem(at: configURL) }
        try fm.moveItem(at: tmp, to: configURL)
    }

    /// 生成被标记包裹的 TOML 块（不含 `[features] hooks`，避免与用户已有 [features] 表重复冲突）。
    func managedBlock() -> String {
        var lines: [String] = [Self.startMarker]
        for event in events {
            lines.append("[[hooks.\(event)]]")
            lines.append("[[hooks.\(event).hooks]]")
            lines.append("type = \"command\"")
            lines.append("command = \"\(reporterCommand)\"")
            lines.append("")
        }
        lines.append(Self.endMarker)
        return lines.joined(separator: "\n")
    }

    public func install() throws {
        var base = readText()
        if base.contains(Self.startMarker) { return }  // 幂等
        if fm.fileExists(atPath: configURL.path) {
            if fm.fileExists(atPath: backupURL.path) { try fm.removeItem(at: backupURL) }
            try fm.copyItem(at: configURL, to: backupURL)
        }
        while base.hasSuffix("\n") { base.removeLast() }  // 规范化尾部换行
        let prefix = base.isEmpty ? "" : base + "\n\n"  // 与用户内容之间留一空行
        try writeText(prefix + managedBlock() + "\n")
        AgentmonLog.shared.info("hook", "已启用 Codex 集成（追加 TOML 标记块）")
    }

    public func uninstall() throws {
        let text = readText()
        guard let start = text.range(of: Self.startMarker),
            let end = text.range(of: Self.endMarker, range: start.upperBound..<text.endIndex)
        else { return }
        var before = String(text[..<start.lowerBound])
        var after = String(text[end.upperBound...])
        while before.hasSuffix("\n") { before.removeLast() }
        while after.hasPrefix("\n") { after.removeFirst() }
        var out = before
        if !before.isEmpty && !after.isEmpty { out += "\n\n" }
        out += after
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        try writeText(out)
        AgentmonLog.shared.info("hook", "已停用 Codex 集成（移除 TOML 标记块）")
    }

    public func isInstalled() throws -> Bool {
        let text = readText()
        return text.contains(Self.startMarker) && text.contains(reporterCommand)
    }
}
