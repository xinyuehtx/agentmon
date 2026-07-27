import XCTest

@testable import agentmonCore

/// Codex TOML 标记块安装器：追加 / 备份 / 幂等 / 精确回滚 / 保留用户内容。
final class CodexHookInstallerTests: XCTestCase {

    private var dir: URL!
    private var configURL: URL!
    private let reporter = "/Applications/agentmon.app/Contents/MacOS/agentmon-hook Codex"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("config.toml")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func read() throws -> String { try String(contentsOf: configURL, encoding: .utf8) }
    private func make() -> CodexHookInstaller {
        CodexHookInstaller(
            configURL: configURL, reporterCommand: reporter,
            events: ["UserPromptSubmit", "PermissionRequest", "Stop"])
    }
    private var backupURL: URL { dir.appendingPathComponent("config.toml.agentmon.bak") }

    func testInstallOnMissingFileCreatesBlock() throws {
        let installer = make()
        try installer.install()
        let out = try read()
        XCTAssertTrue(out.contains(CodexHookInstaller.startMarker))
        XCTAssertTrue(out.contains("[[hooks.UserPromptSubmit]]"))
        XCTAssertTrue(out.contains("[[hooks.PermissionRequest]]"))
        XCTAssertTrue(out.contains("[[hooks.Stop]]"))
        XCTAssertTrue(out.contains(reporter))
        XCTAssertTrue(try installer.isInstalled())
    }

    func testInstallBacksUpExistingAndPreservesUserContent() throws {
        try "[model]\nname = \"gpt\"\n".data(using: .utf8)!.write(to: configURL)
        let installer = make()
        try installer.install()
        let out = try read()
        XCTAssertTrue(out.contains("name = \"gpt\""))  // 用户内容保留
        XCTAssertTrue(out.contains(CodexHookInstaller.startMarker))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testInstallIsIdempotent() throws {
        let installer = make()
        try installer.install()
        try installer.install()
        let out = try read()
        let markerCount = out.components(separatedBy: CodexHookInstaller.startMarker).count - 1
        XCTAssertEqual(markerCount, 1)  // 不重复注入
    }

    func testUninstallRemovesBlockAndPreservesUserContent() throws {
        try "[model]\nname = \"gpt\"\n".data(using: .utf8)!.write(to: configURL)
        let installer = make()
        try installer.install()
        try installer.uninstall()
        let out = try read()
        XCTAssertTrue(out.contains("name = \"gpt\""))
        XCTAssertFalse(out.contains(CodexHookInstaller.startMarker))
        XCTAssertFalse(out.contains(CodexHookInstaller.endMarker))
        XCTAssertFalse(out.contains(reporter))
        XCTAssertFalse(try installer.isInstalled())
    }

    func testUninstallWithoutInstallIsNoop() throws {
        let installer = make()
        try installer.uninstall()  // 文件不存在
        XCTAssertFalse(try installer.isInstalled())
    }
}
