import XCTest

@testable import agentmonCore

/// hook 事件名 → 任务事件的映射（含 Qoder 的 SubagentStart/Stop）。
final class ClaudeEventMapperTests: XCTestCase {

    private let ts = Date(timeIntervalSince1970: 1)

    private func map(_ name: String) -> TaskEvent? {
        ClaudeEventMapper.map(hookEventName: name, client: "Qoder", sessionID: "s", timestamp: ts)
    }

    func testMappings() {
        XCTAssertEqual(map("UserPromptSubmit")?.kind, .start)
        XCTAssertEqual(map("SubagentStart")?.kind, .start)
        XCTAssertEqual(map("Notification")?.kind, .pause)
        XCTAssertEqual(map("Stop")?.kind, .end)
        XCTAssertNil(map("SubagentStop"))  // 有意忽略，避免与 Stop 重复计完成
        XCTAssertNil(map("PreToolUse"))
    }

    func testClientPassedThrough() {
        XCTAssertEqual(map("Stop")?.client, "Qoder")
    }
}
