import XCTest

@testable import agentmonCore

/// AppSettings 读写：round-trip、缺失回退默认、向后兼容解码、原子写。
final class AppSettingsStoreTests: XCTestCase {

    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-appsettings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("app-settings.json")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileReturnsDefault() {
        let store = AppSettingsStore(url: url)
        XCTAssertEqual(store.load(), .default)
    }

    func testRoundTrip() throws {
        let store = AppSettingsStore(url: url)
        var s = AppSettings.default
        s.customPaths = ["codex": "/tmp/c.toml", "opencode": "/tmp/a.js"]
        s.petVisible = false
        s.petScale = 1.5
        s.petOrigin = [10, 20]
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testBackwardCompatDecodeMissingFields() throws {
        try Data(#"{"petVisible":false}"#.utf8).write(to: url)
        let s = AppSettingsStore(url: url).load()
        XCTAssertFalse(s.petVisible)
        XCTAssertEqual(s.schemaVersion, 1)
        XCTAssertEqual(s.customPaths, [:])
        XCTAssertNil(s.petScale)
    }
}
