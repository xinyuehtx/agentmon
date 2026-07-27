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
        let old = try store.loadState()
        XCTAssertNil(old?.species)
        XCTAssertNil(old?.starveMinutes)
        XCTAssertNil(old?.graduated)
        XCTAssertNil(old?.displaySkin)
    }

    func testLifecycleFieldsRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = StateStore(
            stateURL: dir.appendingPathComponent("state.json"),
            configURL: dir.appendingPathComponent("config.json"))

        let s = PersistentState(
            energy: 0, level: 5, completedByClient: [:],
            lastTick: Date(timeIntervalSince1970: 1), completedDay: "2026-07-25",
            species: "dog_cabbage", starveMinutes: 120, graduated: ["bird_fire"],
            displaySkin: "bird_fire", displayStage: "mature")
        try store.saveState(s)
        let loaded = try store.loadState()
        XCTAssertEqual(loaded?.starveMinutes, 120)
        XCTAssertEqual(loaded?.graduated, ["bird_fire"])
        XCTAssertEqual(loaded?.displaySkin, "bird_fire")
        XCTAssertEqual(loaded?.displayStage, "mature")
    }

    func testEnergyConfigBackwardCompatDecode() throws {
        // 旧 config.json（无 graduationLevel/starveDeathMinutes）→ 用默认值，保留用户已调项
        let data = Data(
            #"{"workingPerMin":5,"waitingPerMin":-2,"completedBonus":40,"idleDecayPerMin":-1,"thresholds":[100,200]}"#
                .utf8)
        let cfg = try JSONDecoder().decode(EnergyConfig.self, from: data)
        XCTAssertEqual(cfg.workingPerMin, 5)
        XCTAssertEqual(cfg.thresholds, [100, 200])
        XCTAssertEqual(cfg.graduationLevel, 5)
        XCTAssertEqual(cfg.starveDeathMinutes, 4320)
    }
}
