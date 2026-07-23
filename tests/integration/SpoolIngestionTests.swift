import XCTest

@testable import agentmonCore

/// 集成测试：spool 目录文件 → 解析/映射 → TaskEvent，且读入即删、损坏跳过、按时间排序。
/// 契约见 specs/agent-task-monitor.md §5.2 / §5.3。
final class SpoolIngestionTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-spool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeSpool(_ name: String, _ json: String) throws {
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }

    private func remainingFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
    }

    // US-D1
    func testDrainMapsStopToEndAndConsumesFile() throws {
        try writeSpool(
            "a.json",
            #"""
            {"hook_event_name":"Stop","session_id":"s1","client":"Claude Code","received_at":"2026-07-23T10:00:00Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .end)
        XCTAssertEqual(events[0].client, "Claude Code")
        XCTAssertEqual(events[0].sessionID, "s1")
        XCTAssertTrue(try remainingFiles().isEmpty)  // 读入即删
    }

    func testMapsUserPromptSubmitToStart() throws {
        try writeSpool(
            "a.json",
            #"""
            {"hook_event_name":"UserPromptSubmit","session_id":"s1","client":"Claude Code","received_at":"2026-07-23T10:00:00Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertEqual(events.map(\.kind), [.start])
    }

    func testMapsNotificationToPause() throws {
        try writeSpool(
            "a.json",
            #"""
            {"hook_event_name":"Notification","session_id":"s1","client":"Claude Code","received_at":"2026-07-23T10:00:00Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertEqual(events.map(\.kind), [.pause])
    }

    // US-D2
    func testCorruptFileSkippedButDeleted() throws {
        try writeSpool("bad.json", "{ not json")
        try writeSpool(
            "good.json",
            #"""
            {"hook_event_name":"UserPromptSubmit","session_id":"s2","client":"Claude Code","received_at":"2026-07-23T10:00:01Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertEqual(events.map(\.kind), [.start])  // 合法文件仍产出
        XCTAssertTrue(try remainingFiles().isEmpty)  // 两者都被清理
    }

    func testEventsSortedByTimestamp() throws {
        try writeSpool(
            "later.json",
            #"""
            {"hook_event_name":"Stop","session_id":"s1","client":"C","received_at":"2026-07-23T10:00:05Z"}
            """#)
        try writeSpool(
            "earlier.json",
            #"""
            {"hook_event_name":"UserPromptSubmit","session_id":"s1","client":"C","received_at":"2026-07-23T10:00:01Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertEqual(events.map(\.kind), [.start, .end])
    }

    func testUnknownHookProducesNoEventButFileDeleted() throws {
        try writeSpool(
            "x.json",
            #"""
            {"hook_event_name":"PreToolUse","session_id":"s1","client":"C","received_at":"2026-07-23T10:00:00Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(try remainingFiles().isEmpty)
    }

    func testTmpFilesAreIgnored() throws {
        try writeSpool(
            "pending.json.tmp",
            #"""
            {"hook_event_name":"Stop","session_id":"s1","client":"C","received_at":"2026-07-23T10:00:00Z"}
            """#)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(try remainingFiles(), ["pending.json.tmp"])  // .tmp 保留不消费
    }
}
