import AppKit

/// App 级别的元信息与共享定位逻辑（供 AppDelegate 与 Doctor 复用）。
enum AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    /// 随包分发的 agentmon-hook 上报器路径（与主程序同目录）。
    static func reporterCommand() -> String {
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            return dir.appendingPathComponent("agentmon-hook").path
        }
        return "agentmon-hook"
    }
}
