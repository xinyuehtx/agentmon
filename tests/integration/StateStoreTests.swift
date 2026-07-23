import XCTest

@testable import agentmonCore

/// 集成测试：state.json / config.json 往返与缺失回退。
final class StateStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore() -> StateStore {
        StateStore(
            stateURL: dir.appendingPathComponent("state.json"),
            configURL: dir.appendingPathComponent("config.json"))
    }

    func testStateRoundTrip() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let s = PersistentState(
            energy: 123.5, level: 3,
            completedByClient: ["Claude Code": 7], lastTick: now)
        try store.saveState(s)
        XCTAssertEqual(try store.loadState(), s)
    }

    func testLoadStateMissingReturnsNil() throws {
        let store = StateStore(
            stateURL: dir.appendingPathComponent("nope.json"),
            configURL: dir.appendingPathComponent("config.json"))
        XCTAssertNil(try store.loadState())
    }

    func testLoadConfigMissingReturnsDefault() throws {
        let store = StateStore(
            stateURL: dir.appendingPathComponent("state.json"),
            configURL: dir.appendingPathComponent("nope.json"))
        XCTAssertEqual(try store.loadConfig(), .default)
    }

    func testConfigRoundTrip() throws {
        let store = makeStore()
        var c = EnergyConfig.default
        c.workingPerMin = 5
        c.thresholds = [100, 250]
        try store.saveConfig(c)
        XCTAssertEqual(try store.loadConfig(), c)
    }
}
