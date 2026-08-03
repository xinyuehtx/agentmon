import Foundation

/// agentmon 的本地路径约定。契约见 specs/agent-task-monitor.md §6。
///
/// 测试隔离：`AGENTMON_HOME` 覆盖数据根目录（spool/state/config 随之重定向），
/// `AGENTMON_CLAUDE_SETTINGS` 覆盖 Claude settings 路径——保证 E2E 不触碰用户真实数据。
public enum AgentmonPaths {
    public static var appSupport: URL {
        if let home = ProcessInfo.processInfo.environment["AGENTMON_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("agentmon", isDirectory: true)
    }
    public static var spool: URL { appSupport.appendingPathComponent("spool", isDirectory: true) }
    public static var stateFile: URL { appSupport.appendingPathComponent("state.json") }
    public static var configFile: URL { appSupport.appendingPathComponent("config.json") }
    public static var logFile: URL { appSupport.appendingPathComponent("agentmon.log") }
    public static var diagnosticsFile: URL { appSupport.appendingPathComponent("diagnostics.txt") }
    public static var appSettingsFile: URL { appSupport.appendingPathComponent("app-settings.json") }
    /// 本地自定义宠物图集目录（用户本地导入的第三方素材放此处；不随仓库/发布分发）。
    public static var customPet: URL { appSupport.appendingPathComponent("custom_pet", isDirectory: true) }

    /// 按 env 覆盖优先、否则家目录默认，解析一个客户端配置路径。
    private static func homePath(env: String, default relative: String) -> URL {
        if let override = ProcessInfo.processInfo.environment[env], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative)
    }

    public static var claudeSettings: URL {
        homePath(env: "AGENTMON_CLAUDE_SETTINGS", default: ".claude/settings.json")
    }

    public static var qoderSettings: URL {
        homePath(env: "AGENTMON_QODER_SETTINGS", default: ".qoder/settings.json")
    }

    /// qoderwork / QwenWork 共用（QwenWorkCN.app 内核为 qoderclicn，配置目录默认 ~/.qoderwork）。
    public static var qoderworkSettings: URL {
        homePath(env: "AGENTMON_QODERWORK_SETTINGS", default: ".qoderwork/settings.json")
    }

    public static var codexConfig: URL {
        homePath(env: "AGENTMON_CODEX_CONFIG", default: ".codex/config.toml")
    }

    public static var opencodePlugin: URL {
        homePath(env: "AGENTMON_OPENCODE_PLUGIN", default: ".config/opencode/plugins/agentmon.js")
    }
}
