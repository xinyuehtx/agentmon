import XCTest

@testable import agentmonCore

/// 宠物物种持久化：往返 + 旧文件（无 species）向后兼容。
final class PetPersistenceTests: XCTestCase {

    func testSpeciesRoundTripAndBackwardCompat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StateStore(
            stateURL: dir.appendingPathComponent("state.json"),
            configURL: dir.appendingPathComponent("config.json"))

        let s = PersistentState(
            energy: 1, level: 2, completedByClient: [:],
            lastTick: Date(timeIntervalSince1970: 1), completedDay: "2026-07-23", species: "ember")
        try store.saveState(s)
        XCTAssertEqual(try store.loadState()?.species, "ember")

        // 旧文件（无 species 字段）→ nil，不报错
        try Data(
            #"{"energy":1,"level":1,"completedByClient":{},"lastTick":"2026-07-23T00:00:00Z"}"#.utf8
        ).write(to: dir.appendingPathComponent("state.json"))
        XCTAssertNil(try store.loadState()?.species)
    }
}
