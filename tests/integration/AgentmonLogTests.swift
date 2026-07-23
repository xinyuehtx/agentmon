import XCTest

@testable import agentmonCore

/// 日志写入 / 尾部读取 / 滚动 / 未配置时不落文件。
final class AgentmonLogTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWritesAndReadsRecentLines() {
        let url = dir.appendingPathComponent("t.log")
        let log = AgentmonLog(fileURL: url)
        log.info("cat", "hello")
        log.warn("cat", "careful")
        log.flush()

        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        XCTAssertTrue(text.contains("[INFO] cat: hello"))
        XCTAssertTrue(text.contains("[WARN] cat: careful"))

        let lines = log.recentLines(1)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("careful"))
    }

    func testRotationKeepsBackup() {
        let url = dir.appendingPathComponent("t.log")
        let log = AgentmonLog(fileURL: url, maxBytes: 200)
        for i in 0..<50 { log.info("c", "message number \(i) with some padding padding") }
        log.flush()

        let backup = url.appendingPathExtension("1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "超过上限应产生 .1 备份")
    }

    func testNoFileWhenUnconfigured() {
        let log = AgentmonLog()  // 无 fileURL
        log.info("c", "x")
        log.flush()
        XCTAssertTrue(log.recentLines(5).isEmpty)
    }
}
