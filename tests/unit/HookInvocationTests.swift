import XCTest

@testable import agentmonCore

/// agentmon-hook 参数/stdin 解析契约：`agentmon-hook <client> [<kind> [<sid>]]`。
final class HookInvocationTests: XCTestCase {

    private func json(_ event: String, _ sid: String) -> Data {
        Data(#"{"hook_event_name":"\#(event)","session_id":"\#(sid)"}"#.utf8)
    }

    func testNeedsStdin() {
        XCTAssertTrue(HookInvocation.needsStdin(arguments: ["hook"]))
        XCTAssertTrue(HookInvocation.needsStdin(arguments: ["hook", "Codex"]))
        XCTAssertFalse(HookInvocation.needsStdin(arguments: ["hook", "opencode", "start"]))
        XCTAssertFalse(HookInvocation.needsStdin(arguments: ["hook", "opencode", "start", "s1"]))
    }

    func testZeroExtraArgsUsesStdinAndDefaultClient() {
        let inv = HookInvocation.resolve(arguments: ["hook"], stdin: json("Stop", "abc"))
        XCTAssertEqual(inv.client, "Claude Code")
        XCTAssertEqual(inv.eventName, "Stop")
        XCTAssertEqual(inv.sessionID, "abc")
    }

    func testOneExtraArgIsClientAndUsesStdin() {
        let inv = HookInvocation.resolve(arguments: ["hook", "Codex"], stdin: json("PermissionRequest", "x"))
        XCTAssertEqual(inv.client, "Codex")
        XCTAssertEqual(inv.eventName, "PermissionRequest")
        XCTAssertEqual(inv.sessionID, "x")
    }

    func testTwoExtraArgsUseNormalizedKindNoStdin() {
        let inv = HookInvocation.resolve(arguments: ["hook", "opencode", "start"], stdin: Data())
        XCTAssertEqual(inv.client, "opencode")
        XCTAssertEqual(inv.eventName, "start")
        XCTAssertEqual(inv.sessionID, "unknown")
    }

    func testThreeExtraArgsCarrySession() {
        let inv = HookInvocation.resolve(arguments: ["hook", "opencode", "end", "s9"], stdin: Data())
        XCTAssertEqual(inv.eventName, "end")
        XCTAssertEqual(inv.sessionID, "s9")
    }

    func testEmptyStdinFallsBack() {
        let inv = HookInvocation.resolve(arguments: ["hook"], stdin: Data())
        XCTAssertEqual(inv.eventName, "Unknown")
        XCTAssertEqual(inv.sessionID, "unknown")
    }
}
