import XCTest

@testable import agentmonCore

/// MonitorCoordinator 生命周期：展示皮肤暂停成长 / 孵化 / 毕业收藏 / 饿死重生。
final class MonitorCoordinatorLifecycleTests: XCTestCase {

    private var dir: URL!
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-life-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeCoord(config: EnergyConfig = .default, energy: Double = 0, level: Int = 1)
        -> MonitorCoordinator
    {
        let engine = EnergyEngine(config: config, energy: energy, level: level, lastTick: t0)
        let coord = MonitorCoordinator(ingestor: SpoolIngestor(directory: dir), engine: engine)
        coord.availableSpecies = ["a", "b", "c"]
        return coord
    }

    func testSkinModePausesGrowth() {
        let coord = makeCoord(energy: 100, level: 2)
        coord.restoreLifecycle(species: "a", graduated: ["b"], displaySkin: nil, displayStage: nil)
        coord.showSkin("b", stage: "mature")

        let snap = coord.pump(now: at(1000))  // 若不暂停，空闲 1000min 会衰减到 0
        XCTAssertEqual(coord.engine.energy, 100, accuracy: 1e-6)  // 成长暂停
        XCTAssertTrue(snap.isSkinMode)
        XCTAssertEqual(snap.displaySpecies, "b")
        XCTAssertEqual(snap.displayStage, "mature")
    }

    func testShowSkinRejectsUngraduated() {
        let coord = makeCoord()
        coord.restoreLifecycle(species: "a", graduated: ["b"], displaySkin: nil, displayStage: nil)
        coord.showSkin("c", stage: "final")  // c 未毕业 → 忽略
        XCTAssertNil(coord.displaySkin)
    }

    func testHatchNewPetResetsAndPicksNewSpecies() {
        let coord = makeCoord(energy: 500, level: 3)
        coord.restoreLifecycle(species: "a", graduated: [], displaySkin: nil, displayStage: nil)
        coord.speciesPicker = { _, _, current in
            XCTAssertEqual(current, "a")
            return "b"
        }
        coord.hatchNewPet(now: at(10))
        XCTAssertEqual(coord.species, "b")
        XCTAssertEqual(coord.engine.level, 1)
        XCTAssertEqual(coord.engine.energy, 0, accuracy: 1e-6)
        XCTAssertNil(coord.displaySkin)
    }

    func testGraduationUnlocksSkinAndFreezes() {
        let coord = makeCoord(energy: 3990, level: 4)
        coord.restoreLifecycle(species: "a", graduated: [], displaySkin: nil, displayStage: nil)
        var graduatedSpecies: String?
        coord.onGraduate = { graduatedSpecies = $0 }

        coord.engine.registerCompletions(1, now: at(1))  // 3990+30 >= 4000 → 毕业
        XCTAssertEqual(coord.graduated, ["a"])
        XCTAssertEqual(graduatedSpecies, "a")
        XCTAssertTrue(coord.snapshot().isGraduated)
    }

    func testStarvationTriggersRebirth() {
        let cfg = EnergyConfig(
            workingPerMin: 2, waitingPerMin: -1, completedBonus: 30, idleDecayPerMin: -0.5,
            thresholds: [300, 900, 2000], graduationLevel: 5, starveDeathMinutes: 100)
        let coord = makeCoord(config: cfg, energy: 0, level: 1)
        coord.restoreLifecycle(species: "a", graduated: [], displaySkin: nil, displayStage: nil)
        coord.speciesPicker = { _, _, _ in "b" }
        var died: String?
        coord.onDeath = { died = $0 }

        coord.pump(now: at(200))  // 空闲能量归零累计 200min ≥ 100 → 饿死重生
        XCTAssertEqual(coord.species, "b")
        XCTAssertEqual(coord.engine.level, 1)
        XCTAssertEqual(coord.engine.starveMinutes, 0, accuracy: 1e-6)
        XCTAssertEqual(died, "a")
    }
}
