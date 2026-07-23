import Foundation

public enum HookInstallError: Error, Equatable {
    case invalidSettingsJSON
}

/// 向用户 `~/.claude/settings.json` 合并注入 / 精确回滚 agentmon 的 hooks。
/// 契约见 specs/agent-task-monitor.md §5.4。
///
/// 安全约束：写前备份、幂等、按 `reporterCommand` 精确定位 agentmon 项、JSON 损坏时中止不写。
public final class ClaudeHookInstaller {

    private let settingsURL: URL
    private let reporterCommand: String
    private let events = ["UserPromptSubmit", "Notification", "Stop"]  // MVP 注入恰好 3 个
    private let fm = FileManager.default

    public init(settingsURL: URL, reporterCommand: String) {
        self.settingsURL = settingsURL
        self.reporterCommand = reporterCommand
    }

    private var backupURL: URL {
        settingsURL.deletingLastPathComponent()
            .appendingPathComponent(settingsURL.lastPathComponent + ".agentmon.bak")
    }

    /// 读取根对象；文件缺失/空 → 空对象；内容非法 JSON 对象 → 抛错（写前守卫）。
    private func loadRoot() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else {
            return [:]
        }
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HookInstallError.invalidSettingsJSON
        }
        return dict
    }

    private func writeRoot(_ root: [String: Any]) throws {
        let raw = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        // JSONSerialization 会把 `/` 转义成 `\/`；还原为 `/`，与 Claude Code 自身写法一致、也更可读。
        let text = String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/")
        let data = Data(text.utf8)
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = settingsURL.appendingPathExtension("tmp")
        try data.write(to: tmp)
        if fm.fileExists(atPath: settingsURL.path) { try fm.removeItem(at: settingsURL) }
        try fm.moveItem(at: tmp, to: settingsURL)
    }

    private func isAgentmonGroup(_ group: Any) -> Bool {
        guard
            let g = group as? [String: Any],
            let hooks = g["hooks"] as? [[String: Any]]
        else { return false }
        return hooks.contains { ($0["command"] as? String) == reporterCommand }
    }

    private func agentmonGroup() -> [String: Any] {
        ["hooks": [["type": "command", "command": reporterCommand]]]
    }

    public func install() throws {
        var root = try loadRoot()  // 非法 JSON 在此抛错，早于任何写入/备份

        if fm.fileExists(atPath: settingsURL.path) {
            if fm.fileExists(atPath: backupURL.path) { try fm.removeItem(at: backupURL) }
            try fm.copyItem(at: settingsURL, to: backupURL)
        }

        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        for event in events {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            if !groups.contains(where: { isAgentmonGroup($0) }) {
                groups.append(agentmonGroup())  // 幂等：已存在则不重复注入
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeRoot(root)
        AgentmonLog.shared.info("hook", "已启用 Claude 集成（注入 \(events.count) 个事件 hook）")
    }

    public func uninstall() throws {
        guard fm.fileExists(atPath: settingsURL.path) else { return }
        var root = try loadRoot()
        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for event in events {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            groups.removeAll { isAgentmonGroup($0) }
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        try writeRoot(root)
        AgentmonLog.shared.info("hook", "已停用 Claude 集成（移除 agentmon hooks）")
    }

    public func isInstalled() throws -> Bool {
        let root = try loadRoot()
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        for event in events {
            if let groups = hooks[event] as? [[String: Any]],
                groups.contains(where: { isAgentmonGroup($0) })
            {
                return true
            }
        }
        return false
    }
}
