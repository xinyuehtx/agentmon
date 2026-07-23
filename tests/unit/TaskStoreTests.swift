import XCTest

@testable import agentmonCore

/// 单元测试：事件 → 每客户端三态计数。
/// 契约见 specs/agent-task-monitor.md §2（含状态机与陈旧/幂等规则）。
final class TaskStoreTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }
    private func ev(
        _ client: String, _ sid: String,
        _ kind: TaskEventKind, _ ts: Date
    ) -> TaskEvent {
        TaskEvent(client: client, sessionID: sid, kind: kind, timestamp: ts)
    }

    // US-A1
    func testStartMarksWorking() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 1, waiting: 0, completed: 0))
        XCTAssertEqual(s.totalWorking, 1)
    }

    // US-A2
    func testPauseMarksWaiting() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Claude Code", "s1", .pause, at(1)))
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 0, waiting: 1, completed: 0))
        XCTAssertEqual(s.totalWaiting, 1)
    }

    // US-A3
    func testEndMarksCompletedAndIdle() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Claude Code", "s1", .end, at(1)))
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 0, waiting: 0, completed: 1))
        XCTAssertEqual(s.totalWorking, 0)
        XCTAssertEqual(s.totalCompleted, 1)
    }

    func testEndFromWaiting() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Claude Code", "s1", .pause, at(1)))
        s.apply(ev("Claude Code", "s1", .end, at(2)))
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 0, waiting: 0, completed: 1))
    }

    // US-D4
    func testEndIsIdempotent() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Claude Code", "s1", .end, at(1)))
        s.apply(ev("Claude Code", "s1", .end, at(2)))  // 再次 end
        XCTAssertEqual(s.totalCompleted, 1)  // 不重复计
    }

    // US-A4
    func testPerClientIsolation() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Codex", "s2", .start, at(0)))
        XCTAssertEqual(s.totalWorking, 2)
        XCTAssertEqual(s.counts(for: "Claude Code").working, 1)
        XCTAssertEqual(s.counts(for: "Codex").working, 1)

        s.apply(ev("Claude Code", "s1", .end, at(1)))
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 0, waiting: 0, completed: 1))
        XCTAssertEqual(s.counts(for: "Codex").working, 1)  // 不受影响
        XCTAssertEqual(s.counts(for: "Codex").completed, 0)
    }

    func testSameSessionIDAcrossClientsDoNotCollide() {
        let s = TaskStore()
        s.apply(ev("A", "same", .start, at(0)))
        s.apply(ev("B", "same", .start, at(0)))
        XCTAssertEqual(s.counts(for: "A").working, 1)
        XCTAssertEqual(s.counts(for: "B").working, 1)
        XCTAssertEqual(s.totalWorking, 2)
    }

    func testMultipleSessionsSameClient() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Claude Code", "s2", .start, at(0)))
        XCTAssertEqual(s.counts(for: "Claude Code").working, 2)
        s.apply(ev("Claude Code", "s1", .pause, at(1)))
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 1, waiting: 1, completed: 0))
    }

    // US-D3
    func testStaleEventIgnored() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(2)))
        s.apply(ev("Claude Code", "s1", .pause, at(1)))  // 迟到、陈旧
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 1, waiting: 0, completed: 0))
    }

    func testResumeViaStart() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Claude Code", "s1", .pause, at(1)))
        s.apply(ev("Claude Code", "s1", .start, at(2)))  // 从等待恢复
        XCTAssertEqual(
            s.counts(for: "Claude Code"),
            ClientCounts(working: 1, waiting: 0, completed: 0))
    }

    func testUnknownClientReturnsZero() {
        let s = TaskStore()
        XCTAssertEqual(
            s.counts(for: "Nope"),
            ClientCounts(working: 0, waiting: 0, completed: 0))
    }

    func testAllClientsInFirstSeenOrder() {
        let s = TaskStore()
        s.apply(ev("Claude Code", "s1", .start, at(0)))
        s.apply(ev("Codex", "s2", .start, at(0)))
        XCTAssertEqual(s.allClients(), ["Claude Code", "Codex"])
    }
}
