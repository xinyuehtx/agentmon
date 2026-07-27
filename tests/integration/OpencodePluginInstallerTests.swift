import XCTest

@testable import agentmonCore

/// opencode 插件安装器：写文件 / 备份他人文件 / 精确回滚 / 标记识别。
final class OpencodePluginInstallerTests: XCTestCase {

    private var dir: URL!
    private var pluginURL: URL!
    private let reporter = "/Applications/agentmon.app/Contents/MacOS/agentmon-hook"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-opencode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pluginURL = dir.appendingPathComponent("plugins/agentmon.js")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func read() throws -> String { try String(contentsOf: pluginURL, encoding: .utf8) }
    private func make() -> OpencodePluginInstaller {
        OpencodePluginInstaller(pluginURL: pluginURL, reporterCommand: reporter, clientLabel: "opencode")
    }

    func testInstallWritesMarkedPluginWithReporterAndClient() throws {
        let installer = make()
        try installer.install()
        let out = try read()
        XCTAssertTrue(out.contains("agentmon-plugin v1"))
        XCTAssertTrue(out.contains(reporter))
        XCTAssertTrue(out.contains("\"opencode\""))
        XCTAssertTrue(out.contains("session.idle"))  // 订阅了结束事件
        XCTAssertTrue(try installer.isInstalled())
    }

    func testInstallBacksUpForeignFile() throws {
        try FileManager.default.createDirectory(
            at: pluginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// someone else's plugin".data(using: .utf8)!.write(to: pluginURL)
        let installer = make()
        try installer.install()
        let backup = dir.appendingPathComponent("plugins/agentmon.js.agentmon.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        XCTAssertTrue(try read().contains("agentmon-plugin v1"))
    }

    func testUninstallRemovesOwnPlugin() throws {
        let installer = make()
        try installer.install()
        try installer.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginURL.path))
        XCTAssertFalse(try installer.isInstalled())
    }

    func testUninstallLeavesForeignFileUntouched() throws {
        try FileManager.default.createDirectory(
            at: pluginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// not ours".data(using: .utf8)!.write(to: pluginURL)
        let installer = make()
        try installer.uninstall()  // 非本插件 → no-op
        XCTAssertTrue(FileManager.default.fileExists(atPath: pluginURL.path))
        XCTAssertEqual(try read(), "// not ours")
    }
}
