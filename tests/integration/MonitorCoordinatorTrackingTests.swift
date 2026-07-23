import XCTest

@testable import agentmonCore

/// MonitorCoordinator 的事件计数/最近事件追踪。
final class MonitorCoordinatorTrackingTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-track-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, _ json: String) throws {
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    func testTracksEventsSeenAndLastEventAt() throws {
        let now = Date(timeIntervalSinceReferenceDate: 5000)
        try write(
            "1.json",
            #"{"hook_event_name":"UserPromptSubmit","session_id":"s1","client":"C","received_at":"2026-07-23T10:00:01Z"}"#
        )
        try write(
            "2.json",
            #"{"hook_event_name":"Notification","session_id":"s1","client":"C","received_at":"2026-07-23T10:00:03Z"}"#
        )

        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir),
            engine: EnergyEngine(lastTick: now))

        let snap = coord.pump(now: now)
        XCTAssertEqual(snap.eventsSeen, 2)
        XCTAssertNotNil(snap.lastEventAt)

        // 无新事件的 pump 不改变累计
        let snap2 = coord.pump(now: now.addingTimeInterval(1))
        XCTAssertEqual(snap2.eventsSeen, 2)
        XCTAssertEqual(snap2.lastEventAt, snap.lastEventAt)
    }

    func testCompletedResetsAcrossDay() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(2 * 86400)
        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir),
            engine: EnergyEngine(lastTick: day1))
        coord.restore(
            completedByClient: ["Claude Code": 5],
            day: MonitorCoordinator.dayString(day1), now: day1)

        XCTAssertEqual(coord.pump(now: day1).totalCompleted, 5)  // 同一天 → 保留
        XCTAssertEqual(coord.pump(now: day2).totalCompleted, 0)  // 跨天 → 清零
    }

    func testRestoreIgnoresStaleDay() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir),
            engine: EnergyEngine(lastTick: day1))
        // 恢复的是「前一天」的计数 → 不应恢复
        coord.restore(
            completedByClient: ["Claude Code": 9],
            day: MonitorCoordinator.dayString(day1.addingTimeInterval(-86400)), now: day1)

        XCTAssertEqual(coord.pump(now: day1).totalCompleted, 0)
    }
}
