import Foundation

/// 集成安装器的统一契约：把 agentmon 上报器接入某客户端（幂等、可回滚、写前备份）。
/// 三种实现：`ClaudeHookInstaller`（JSON settings.json hooks）、`CodexHookInstaller`（TOML 标记块）、
/// `OpencodePluginInstaller`（JS 插件文件）。契约见 rfcs/multi-client-and-control-panel.md §4.1。
public protocol IntegrationInstaller: AnyObject {
    func install() throws
    func uninstall() throws
    func isInstalled() throws -> Bool
}

/// 客户端接入机制。决定 `IntegrationRegistry` 构造哪种安装器。
public enum IntegrationMechanism: String, Codable, Equatable {
    case claudeHooks  // ~/.<client>/settings.json 的 hooks.<Event>[]（JSON）
    case codexHooks  // ~/.codex/config.toml 的 [[hooks.*]]（TOML 标记块）
    case opencodePlugin  // ~/.config/opencode/plugins/agentmon.js（JS 插件）
}

/// 客户端集成的静态描述符（数据驱动）：UI 与注册表都以此为准迭代。
public struct ClientIntegration: Identifiable, Equatable {
    public let id: String  // "claude"/"qoder"/"qoderwork"/"codex"/"opencode"
    public let displayName: String  // UI 展示名
    public let clientLabel: String  // 写入 spool 的 client 字段（TaskStore 分组键）；须为单个 shell token
    public let symbol: String  // SF Symbol 名（UI 图标）
    public let mechanism: IntegrationMechanism
    public let defaultPath: URL  // 默认 settings/config/plugin 路径
    public let events: [String]  // claudeHooks/codexHooks 的事件列表（plugin 为空）
    public let verified: Bool  // false = 路径为最佳猜测
    public let note: String?  // UI 副标题（如「对 qoderwork 与 QwenWork 都生效」/「启用后需 /hooks 信任」）

    public init(
        id: String,
        displayName: String,
        clientLabel: String,
        symbol: String,
        mechanism: IntegrationMechanism,
        defaultPath: URL,
        events: [String],
        verified: Bool = true,
        note: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.clientLabel = clientLabel
        self.symbol = symbol
        self.mechanism = mechanism
        self.defaultPath = defaultPath
        self.events = events
        self.verified = verified
        self.note = note
    }
}

extension ClaudeHookInstaller: IntegrationInstaller {}
