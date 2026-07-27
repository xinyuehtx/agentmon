import Foundation
import agentmonCore

/// `--doctor`：无 GUI 打印诊断报告后退出，供用户/CI 自查监控为何不工作。
enum Doctor {
    static func run() -> Never {
        AgentmonLog.shared.configure(fileURL: AgentmonPaths.logFile)
        let reporter = AppInfo.reporterCommand()
        let integrations = IntegrationRegistry.descriptors().map {
            Diagnostics.IntegrationStatus(
                descriptor: $0,
                installer: IntegrationRegistry.installer(for: $0, reporterCommand: reporter))
        }
        let report = Diagnostics.report(
            appVersion: AppInfo.version,
            reporterCommand: reporter,
            integrations: integrations,
            spool: AgentmonPaths.spool,
            stateFile: AgentmonPaths.stateFile,
            now: Date(),
            recentLog: AgentmonLog.shared.recentLines(20))
        print(report)
        exit(0)
    }
}
