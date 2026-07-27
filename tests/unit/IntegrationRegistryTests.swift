import XCTest

@testable import agentmonCore

/// 集成注册表：描述符集合、默认路径、自定义路径覆盖、工厂按机制返回正确类型。
final class IntegrationRegistryTests: XCTestCase {

    func testDescriptorsCoverExactlyFiveClients() {
        let ids = IntegrationRegistry.descriptors().map(\.id)
        XCTAssertEqual(ids, ["claude", "qoder", "qoderwork", "codex", "opencode"])
        XCTAssertFalse(ids.contains("qoderwake"))  // 评审②：本期不做
        XCTAssertFalse(ids.contains("qwen"))
    }

    func testDefaultPaths() {
        let d = Dictionary(uniqueKeysWithValues: IntegrationRegistry.descriptors().map { ($0.id, $0) })
        XCTAssertTrue(d["qoderwork"]!.defaultPath.path.hasSuffix(".qoderwork/settings.json"))
        XCTAssertTrue(d["codex"]!.defaultPath.path.hasSuffix(".codex/config.toml"))
        XCTAssertTrue(d["opencode"]!.defaultPath.path.hasSuffix("plugins/agentmon.js"))
    }

    func testQoderworkNoteMentionsBothApps() {
        let qw = IntegrationRegistry.descriptors().first { $0.id == "qoderwork" }!
        XCTAssertNotNil(qw.note)
        XCTAssertTrue(qw.note!.contains("qoderwork"))
        XCTAssertTrue(qw.note!.contains("QwenWork"))
    }

    func testCustomPathOverridesDefault() {
        let ds = IntegrationRegistry.descriptors(customPaths: ["codex": "/tmp/custom.toml"])
        let codex = ds.first { $0.id == "codex" }!
        XCTAssertEqual(codex.defaultPath.path, "/tmp/custom.toml")
    }

    func testFactoryReturnsMechanismSpecificType() {
        let ds = Dictionary(uniqueKeysWithValues: IntegrationRegistry.descriptors().map { ($0.id, $0) })
        let reporter = "/x/agentmon-hook"
        XCTAssertTrue(
            IntegrationRegistry.installer(for: ds["claude"]!, reporterCommand: reporter) is ClaudeHookInstaller)
        XCTAssertTrue(IntegrationRegistry.installer(for: ds["codex"]!, reporterCommand: reporter) is CodexHookInstaller)
        XCTAssertTrue(
            IntegrationRegistry.installer(for: ds["opencode"]!, reporterCommand: reporter)
                is OpencodePluginInstaller)
    }
}
