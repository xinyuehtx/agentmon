import XCTest

@testable import agentmonCore

/// MonitorCoordinator.recentActivity()：pump 后活动流最新在前、有界。
final class MonitorCoordinatorActivityTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ name: String, event: String, sid: String, at: String) throws {
        let json =
            #"{"hook_event_name":"\#(event)","session_id":"\#(sid)","client":"C","received_at":"\#(at)"}"#
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    func testRecentActivityMostRecentFirst() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9000)
        try write("1.json", event: "UserPromptSubmit", sid: "s1", at: "2026-07-23T10:00:01Z")
        try write("2.json", event: "Notification", sid: "s1", at: "2026-07-23T10:00:03Z")
        try write("3.json", event: "Stop", sid: "s1", at: "2026-07-23T10:00:05Z")

        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir), engine: EnergyEngine(lastTick: now))
        _ = coord.pump(now: now)

        let recent = coord.recentActivity(limit: 10)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.first?.kind, .end)  // 最新（Stop）在前
        XCTAssertEqual(recent.last?.kind, .start)
    }

    func testRecentActivityRespectsLimit() throws {
        let now = Date(timeIntervalSinceReferenceDate: 9000)
        for i in 0..<5 {
            try write(
                "\(i).json", event: "UserPromptSubmit", sid: "s\(i)",
                at: "2026-07-23T10:00:0\(i)Z")
        }
        let coord = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir), engine: EnergyEngine(lastTick: now))
        _ = coord.pump(now: now)
        XCTAssertEqual(coord.recentActivity(limit: 2).count, 2)
    }
}
