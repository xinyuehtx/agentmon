import Foundation

/// 客户端集成的数据驱动注册表：唯一真源，供 AppDelegate 构建安装器、UI 迭代展示。
/// 契约见 rfcs/multi-client-and-control-panel.md §4.1。
public enum IntegrationRegistry {

    /// 全部集成描述符。`customPaths[id]` 覆盖默认路径（用户在面板改过的路径）。
    /// 共 5 个：Claude Code / Qoder / qoderwork·QwenWork / Codex / opencode。
    public static func descriptors(customPaths: [String: String] = [:]) -> [ClientIntegration] {
        func path(_ id: String, _ fallback: URL) -> URL {
            if let custom = customPaths[id], !custom.isEmpty { return URL(fileURLWithPath: custom) }
            return fallback
        }

        return [
            ClientIntegration(
                id: "claude", displayName: "Claude Code", clientLabel: "Claude Code",
                symbol: "sparkles", mechanism: .claudeHooks,
                defaultPath: path("claude", AgentmonPaths.claudeSettings),
                events: ["UserPromptSubmit", "Notification", "Stop"]),
            ClientIntegration(
                id: "qoder", displayName: "Qoder", clientLabel: "Qoder",
                symbol: "cube", mechanism: .claudeHooks,
                defaultPath: path("qoder", AgentmonPaths.qoderSettings),
                events: ["UserPromptSubmit", "Notification", "Stop", "SubagentStart"]),
            ClientIntegration(
                id: "qoderwork", displayName: "qoderwork / QwenWork", clientLabel: "qoderwork",
                symbol: "briefcase", mechanism: .claudeHooks,
                defaultPath: path("qoderwork", AgentmonPaths.qoderworkSettings),
                events: ["UserPromptSubmit", "Notification", "Stop", "SubagentStart"],
                note: "对 qoderwork 与 QwenWork 两个应用都生效"),
            ClientIntegration(
                id: "codex", displayName: "Codex", clientLabel: "Codex",
                symbol: "chevron.left.forwardslash.chevron.right", mechanism: .codexHooks,
                defaultPath: path("codex", AgentmonPaths.codexConfig),
                events: ["UserPromptSubmit", "PermissionRequest", "Stop"],
                note: "启用后需在 Codex 里执行一次 /hooks 信任本 hook"),
            ClientIntegration(
                id: "opencode", displayName: "opencode", clientLabel: "opencode",
                symbol: "curlybraces", mechanism: .opencodePlugin,
                defaultPath: path("opencode", AgentmonPaths.opencodePlugin),
                events: []),
        ]
    }

    /// 描述符 + 上报器二进制路径 → 具体安装器。
    /// - `reporterCommand`: agentmon-hook 的绝对路径（不含客户端参数）。
    public static func installer(
        for d: ClientIntegration, reporterCommand: String
    ) -> IntegrationInstaller {
        switch d.mechanism {
        case .claudeHooks:
            // Claude 用裸命令（hook 默认客户端名即 "Claude Code"）；其余追加单 token 客户端标签。
            let command = d.id == "claude" ? reporterCommand : "\(reporterCommand) \(d.clientLabel)"
            return ClaudeHookInstaller(
                settingsURL: d.defaultPath, reporterCommand: command, events: d.events)
        case .codexHooks:
            return CodexHookInstaller(
                configURL: d.defaultPath,
                reporterCommand: "\(reporterCommand) \(d.clientLabel)", events: d.events)
        case .opencodePlugin:
            return OpencodePluginInstaller(
                pluginURL: d.defaultPath, reporterCommand: reporterCommand,
                clientLabel: d.clientLabel)
        }
    }
}
