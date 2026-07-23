import XCTest

/// E2E（XCUITest）：通过真实 spool → pump → UI 链路驱动，断言宠物窗（NSPanel）状态。
///
/// 隔离：`AGENTMON_HOME` 把 spool/state/config 重定向到临时目录，绝不触碰用户真实数据；
/// `AGENTMON_UITEST` 让 App 以 .regular 激活策略运行，便于 XCUITest 稳定寻址窗口。
/// menubar 的 NSStatusItem 不在 app 窗口树内、无法被 XCUITest 寻址，故不在此断言。
final class PetPanelUITests: XCTestCase {

    private var home: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("spool"),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func writeSpool(_ event: String, session: String) throws {
        let ts = ISO8601DateFormatter().string(from: Date())
        let json = """
            {"hook_event_name":"\(event)","session_id":"\(session)",\
            "client":"Claude Code","received_at":"\(ts)"}
            """
        let file = home.appendingPathComponent("spool/\(UUID().uuidString).json")
        try Data(json.utf8).write(to: file)
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AGENTMON_HOME"] = home.path
        app.launchEnvironment["AGENTMON_UITEST"] = "1"
        app.launch()
        return app
    }

    /// 启动前已有一个进行中的任务 → 宠物应显示 working。
    func testPetShowsWorking() throws {
        try writeSpool("UserPromptSubmit", session: "s1")
        let app = launchedApp()

        let state = app.staticTexts["pet.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 15), "宠物窗未出现或无障碍不可见")
        let value = (state.value as? String) ?? ""
        XCTAssertTrue(value.hasPrefix("working:"), "期望 working:*，实际 \(value)")
    }

    /// 任务结束（Stop）后回落到 idle，且累计完成 +能量（宠物窗仍在）。
    func testPetReturnsToIdleAfterCompletion() throws {
        try writeSpool("UserPromptSubmit", session: "s1")
        let app = launchedApp()

        let state = app.staticTexts["pet.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 15))

        try writeSpool("Stop", session: "s1")
        // App 每 2s pump 一次；轮询等待值切换到 idle。
        let deadline = Date().addingTimeInterval(15)
        var value = (state.value as? String) ?? ""
        while !value.hasPrefix("idle:") && Date() < deadline {
            usleep(500_000)
            value = (state.value as? String) ?? ""
        }
        XCTAssertTrue(value.hasPrefix("idle:"), "完成后应回落 idle:*，实际 \(value)")
    }
}
