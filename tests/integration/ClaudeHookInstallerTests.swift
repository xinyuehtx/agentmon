import XCTest

@testable import agentmonCore

/// 集成测试：向用户 ~/.claude/settings.json 合并注入 / 幂等 / 精确回滚 / 损坏保护。
/// 契约见 specs/agent-task-monitor.md §5.4。测试全部指向临时 settings 文件，绝不触碰真实配置。
final class ClaudeHookInstallerTests: XCTestCase {

    private var tmpDir: URL!
    private var settingsURL: URL!
    /// reporterCommand 内含可识别标记 "agentmon-hook"，据此定位/移除 agentmon 注入项。
    private let reporter = "/Applications/agentmon.app/Contents/Resources/agentmon-hook"

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        settingsURL = tmpDir.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func writeSettings(_ json: String) throws {
        try json.data(using: .utf8)!.write(to: settingsURL)
    }
    private func readSettings() throws -> String {
        try String(contentsOf: settingsURL, encoding: .utf8)
    }
    private func makeInstaller() -> ClaudeHookInstaller {
        ClaudeHookInstaller(settingsURL: settingsURL, reporterCommand: reporter)
    }
    private var backupURL: URL {
        tmpDir.appendingPathComponent("settings.json.agentmon.bak")
    }

    // US-C1
    func testInstallMergesAndKeepsUserHooksAndBacksUp() throws {
        try writeSettings(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-own-hook"}]}]}}"#)
        let installer = makeInstaller()
        try installer.install()

        let out = try readSettings()
        XCTAssertTrue(out.contains("my-own-hook"))  // 用户 hook 保留
        XCTAssertTrue(out.contains("agentmon-hook"))  // agentmon 注入
        XCTAssertTrue(try installer.isInstalled())
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))  // 备份存在
    }

    // US-C2
    func testInstallIsIdempotent() throws {
        try writeSettings("{}")
        let installer = makeInstaller()
        try installer.install()
        try installer.install()  // 再次

        let out = try readSettings()
        // MVP 注入恰好 3 个事件 → reporter 命令恰好出现 3 次（无重复）
        let occurrences = out.components(separatedBy: reporter).count - 1
        XCTAssertEqual(occurrences, 3)
        XCTAssertTrue(try installer.isInstalled())
    }

    // US-C3
    func testUninstallRemovesOnlyAgentmonEntries() throws {
        try writeSettings(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-own-hook"}]}]}}"#)
        let installer = makeInstaller()
        try installer.install()
        try installer.uninstall()

        let out = try readSettings()
        XCTAssertTrue(out.contains("my-own-hook"))  // 用户 hook 完好
        XCTAssertFalse(out.contains("agentmon-hook"))  // agentmon 项已清
        XCTAssertFalse(try installer.isInstalled())
    }

    func testUninstallWithoutInstallIsNoop() throws {
        try writeSettings(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"my-own-hook"}]}]}}"#)
        let installer = makeInstaller()
        try installer.uninstall()  // 从未 install
        let out = try readSettings()
        XCTAssertTrue(out.contains("my-own-hook"))
        XCTAssertFalse(try installer.isInstalled())
    }

    func testInstallWhenNoSettingsFileCreatesMinimalValid() throws {
        // settingsURL 尚不存在
        let installer = makeInstaller()
        try installer.install()
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertTrue(try installer.isInstalled())
    }

    // US-C4
    func testCorruptSettingsThrowsAndDoesNotWrite() throws {
        try writeSettings("{ not valid json")
        let installer = makeInstaller()
        XCTAssertThrowsError(try installer.install())
        XCTAssertEqual(try readSettings(), "{ not valid json")  // 原文件不被破坏
    }
}
