import XCTest

@testable import agentmonCore

/// Qoder 集成：复用通用 hook 安装器，注入可配置的事件集到 ~/.qoder/settings.json。
final class QoderInstallTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-qoder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testInstallWithCustomEventsAndUninstall() throws {
        let settings = dir.appendingPathComponent("settings.json")
        let reporter = "/Applications/agentmon.app/Contents/MacOS/agentmon-hook Qoder"
        let installer = ClaudeHookInstaller(
            settingsURL: settings, reporterCommand: reporter,
            events: ["UserPromptSubmit", "Notification", "Stop", "SubagentStart"])

        try installer.install()
        let out = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertEqual(out.components(separatedBy: reporter).count - 1, 4)  // 4 事件各一次
        XCTAssertTrue(out.contains("SubagentStart"))
        XCTAssertTrue(try installer.isInstalled())

        try installer.uninstall()
        XCTAssertFalse(try installer.isInstalled())
    }

    func testPreservesUserHooks() throws {
        let settings = dir.appendingPathComponent("settings.json")
        try Data(
            #"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-qoder-hook"}]}]}}"#.utf8
        ).write(to: settings)
        let installer = ClaudeHookInstaller(
            settingsURL: settings, reporterCommand: "/x/agentmon-hook Qoder",
            events: ["Stop", "SubagentStart"])

        try installer.install()
        let out = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertTrue(out.contains("my-qoder-hook"))  // 用户原有 hook 保留
        XCTAssertTrue(out.contains("/x/agentmon-hook Qoder"))

        try installer.uninstall()
        let after = try String(contentsOf: settings, encoding: .utf8)
        XCTAssertTrue(after.contains("my-qoder-hook"))
        XCTAssertFalse(after.contains("agentmon-hook"))
    }
}
