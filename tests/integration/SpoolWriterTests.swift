import XCTest

@testable import agentmonCore

/// 集成测试：SpoolWriter 原子写 → SpoolIngestor 读回 的往返。
final class SpoolWriterTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-spoolw-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWriteThenDrainRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)  // 整秒，ISO8601 可精确往返
        try SpoolWriter.write(
            hookEventName: "Stop", sessionID: "s1", client: "Claude Code",
            receivedAt: now, directory: dir)
        let events = try SpoolIngestor(directory: dir).drain()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .end)
        XCTAssertEqual(events[0].sessionID, "s1")
        XCTAssertEqual(events[0].client, "Claude Code")
        XCTAssertEqual(events[0].timestamp, now)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(remaining.isEmpty)  // 读入即删
    }

    func testWriteCreatesDirectoryAndLeavesNoTmp() throws {
        try SpoolWriter.write(
            hookEventName: "UserPromptSubmit", sessionID: "s1", client: "C",
            receivedAt: Date(timeIntervalSince1970: 1), directory: dir)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(".json"))
        XCTAssertFalse(files[0].hasSuffix(".tmp"))  // temp 已 rename
    }
}
