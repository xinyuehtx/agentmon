import XCTest

@testable import agentmonCore

/// TaskStore.sessionRows()：每会话一行、状态正确、按最近活动降序（控制台看板用）。
final class TaskStoreSessionRowsTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func ev(_ client: String, _ sid: String, _ kind: TaskEventKind, _ offset: TimeInterval)
        -> TaskEvent
    {
        TaskEvent(client: client, sessionID: sid, kind: kind, timestamp: t0.addingTimeInterval(offset))
    }

    func testRowsReflectStateAndSortDescending() {
        let store = TaskStore()
        store.apply(ev("Claude Code", "s1", .start, 0))  // working
        store.apply(ev("Qoder", "s2", .start, 1))
        store.apply(ev("Qoder", "s2", .pause, 2))  // waiting
        store.apply(ev("Codex", "s3", .start, 3))
        store.apply(ev("Codex", "s3", .end, 4))  // idle（完成后回空闲）

        let rows = store.sessionRows()
        XCTAssertEqual(rows.count, 3)
        // 最近活动降序：s3(4) > s2(2) > s1(0)
        XCTAssertEqual(rows.map(\.sessionID), ["s3", "s2", "s1"])

        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.sessionID, $0) })
        XCTAssertEqual(byID["s1"]?.state, "working")
        XCTAssertEqual(byID["s1"]?.client, "Claude Code")
        XCTAssertEqual(byID["s2"]?.state, "waiting")
        XCTAssertEqual(byID["s3"]?.state, "idle")
    }
}
