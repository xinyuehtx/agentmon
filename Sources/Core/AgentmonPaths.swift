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

    public static var claudeSettings: URL {
        if let override = ProcessInfo.processInfo.environment["AGENTMON_CLAUDE_SETTINGS"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }
}
