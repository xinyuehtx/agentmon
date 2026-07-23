import Foundation

/// agentmon 的本地路径约定。契约见 specs/agent-task-monitor.md §6。
public enum AgentmonPaths {
    public static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("agentmon", isDirectory: true)
    }
    public static var spool: URL { appSupport.appendingPathComponent("spool", isDirectory: true) }
    public static var stateFile: URL { appSupport.appendingPathComponent("state.json") }
    public static var configFile: URL { appSupport.appendingPathComponent("config.json") }

    public static var claudeSettings: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }
}
