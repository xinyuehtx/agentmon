import Foundation
import agentmonCore

/// `--doctor`：无 GUI 打印诊断报告后退出，供用户/CI 自查监控为何不工作。
enum Doctor {
    static func run() -> Never {
        AgentmonLog.shared.configure(fileURL: AgentmonPaths.logFile)
        let installer = ClaudeHookInstaller(
            settingsURL: AgentmonPaths.claudeSettings,
            reporterCommand: AppInfo.reporterCommand())
        let qoderInstaller = ClaudeHookInstaller(
            settingsURL: AgentmonPaths.qoderSettings,
            reporterCommand: "\(AppInfo.reporterCommand()) Qoder",
            events: ["UserPromptSubmit", "Notification", "Stop", "SubagentStart"])
        let report = Diagnostics.report(
            appVersion: AppInfo.version,
            claudeSettings: AgentmonPaths.claudeSettings,
            reporterCommand: AppInfo.reporterCommand(),
            installer: installer,
            spool: AgentmonPaths.spool,
            stateFile: AgentmonPaths.stateFile,
            now: Date(),
            recentLog: AgentmonLog.shared.recentLines(20),
            qoderSettings: AgentmonPaths.qoderSettings,
            qoderInstaller: qoderInstaller)
        print(report)
        exit(0)
    }
}
