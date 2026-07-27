import XCTest

@testable import agentmonCore

/// 诊断报告内容测试（注入临时路径与安装器，走注册表化的新签名）。
final class DiagnosticsTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func claudeStatus(settings: URL, reporter: String) -> Diagnostics.IntegrationStatus {
        let d = ClientIntegration(
            id: "claude", displayName: "Claude Code", clientLabel: "Claude Code",
            symbol: "sparkles", mechanism: .claudeHooks, defaultPath: settings,
            events: ["UserPromptSubmit", "Notification", "Stop"])
        return Diagnostics.IntegrationStatus(
            descriptor: d, installer: ClaudeHookInstaller(settingsURL: settings, reporterCommand: reporter))
    }

    func testReportWhenNotInstalledAndNoState() {
        let settings = dir.appendingPathComponent("settings.json")  // 不创建
        let reporter = dir.appendingPathComponent("agentmon-hook").path

        let report = Diagnostics.report(
            appVersion: "9.9",
            reporterCommand: reporter,
            integrations: [claudeStatus(settings: settings, reporter: reporter)],
            spool: dir.appendingPathComponent("spool"),
            stateFile: dir.appendingPathComponent("state.json"),
            now: Date(timeIntervalSince1970: 1_700_000_000),
            recentLog: [])

        XCTAssertTrue(report.contains("v9.9"))
        XCTAssertTrue(report.contains("未启用 ✗"))
        XCTAssertTrue(report.contains("state.json 未生成"))
        XCTAssertTrue(report.contains("尚未启用任何集成"))
    }

    func testReportWhenInstalledWithState() throws {
        let settings = dir.appendingPathComponent("settings.json")
        let reporter = dir.appendingPathComponent("agentmon-hook").path
        FileManager.default.createFile(
            atPath: reporter, contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755])

        let status = claudeStatus(settings: settings, reporter: reporter)
        try status.installer.install()

        let store = StateStore(
            stateURL: dir.appendingPathComponent("state.json"),
            configURL: dir.appendingPathComponent("config.json"))
        try store.saveState(
            PersistentState(
                energy: 150, level: 2, completedByClient: ["Claude Code": 4],
                lastTick: Date(timeIntervalSince1970: 1_700_000_000)))

        let report = Diagnostics.report(
            appVersion: "1.0",
            reporterCommand: reporter,
            integrations: [status],
            spool: dir.appendingPathComponent("spool"),
            stateFile: dir.appendingPathComponent("state.json"),
            now: Date(timeIntervalSince1970: 1_700_000_005),
            recentLog: ["line-a", "line-b"])

        XCTAssertTrue(report.contains("已启用 ✓"))
        XCTAssertTrue(report.contains("可执行：是"))
        XCTAssertTrue(report.contains("Lv2"))
        XCTAssertTrue(report.contains("Claude Code：累计完成 4"))
        XCTAssertTrue(report.contains("line-b"))
    }
}
