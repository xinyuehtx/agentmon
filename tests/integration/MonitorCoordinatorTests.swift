import XCTest

@testable import agentmonCore

/// 集成测试：MonitorCoordinator 端到端 —— spool 文件 → 摄取 → 计数 → 能量结算 → 快照。
final class MonitorCoordinatorTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ json: String) throws {
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    func testPumpIngestsScoresCompletionAndSnapshots() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1000)
        try write(
            "1.json",
            #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","client":"Claude Code","received_at":"2026-07-23T10:00:01Z"}"#
        )
        try write(
            "2.json",
            #"{"hook_event_name":"Stop","session_id":"s1","client":"Claude Code","received_at":"2026-07-23T10:00:05Z"}"#
        )

        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir),
            engine: EnergyEngine(energy: 0, level: 1, lastTick: now)
        )
        let snap = coord.pump(now: now)  // now == lastTick → tick 增量 0，仅完成加成生效

        XCTAssertEqual(snap.totalCompleted, 1)
        XCTAssertEqual(snap.totalWorking, 0)
        XCTAssertEqual(snap.totalWaiting, 0)
        XCTAssertEqual(snap.energy, 30, accuracy: 1e-6)
        XCTAssertEqual(snap.level, 1)
        XCTAssertEqual(snap.clients.first?.client, "Claude Code")
        XCTAssertEqual(snap.clients.first?.counts.completed, 1)
    }

    func testPumpWorkingAccruesEnergy() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)  // 2001-01-01T00:00:00Z
        try write(
            "1.json",
            #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","client":"C","received_at":"2001-01-01T00:00:00Z"}"#
        )

        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir),
            engine: EnergyEngine(energy: 0, level: 1, lastTick: t0)
        )
        let snap = coord.pump(now: t0.addingTimeInterval(600))  // 10 分钟后，1 个工作中

        XCTAssertEqual(snap.totalWorking, 1)
        XCTAssertEqual(snap.energy, 20, accuracy: 1e-6)  // +2 * 1 * 10min
    }
}
