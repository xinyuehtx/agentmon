import XCTest

@testable import agentmonCore

/// 可种子 RNG（LCG），用于确定性测试。
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

final class PetSelectionTests: XCTestCase {

    func testStageMapping() {
        XCTAssertEqual(PetSelection.stage(forLevel: 0), "egg")
        XCTAssertEqual(PetSelection.stage(forLevel: 1), "egg")
        XCTAssertEqual(PetSelection.stage(forLevel: 2), "juvenile")
        XCTAssertEqual(PetSelection.stage(forLevel: 3), "mature")
        XCTAssertEqual(PetSelection.stage(forLevel: 4), "final")
        XCTAssertEqual(PetSelection.stage(forLevel: 99), "final")
    }

    func testChooseDeterministicAndValid() {
        let ids = ["sprout", "ember", "aqua"]
        var rng = SeededRNG(seed: 42)
        let a = PetSelection.choose(speciesIDs: ids, using: &rng)
        XCTAssertNotNil(a)
        XCTAssertTrue(ids.contains(a!))
        var rng2 = SeededRNG(seed: 42)
        XCTAssertEqual(PetSelection.choose(speciesIDs: ids, using: &rng2), a)  // 同种子重放一致
    }

    func testChooseEmptyReturnsNil() {
        var rng = SeededRNG(seed: 1)
        XCTAssertNil(PetSelection.choose(speciesIDs: [], using: &rng))
    }

    func testNextSpeciesPrefersUnraised() {
        let ids = ["a", "b", "c"]
        var rng = SeededRNG(seed: 7)
        // 已毕业 a、当前 b → 只能挑 c（唯一未毕业且非当前）
        let pick = PetSelection.nextSpecies(
            available: ids, graduated: ["a"], current: "b", using: &rng)
        XCTAssertEqual(pick, "c")
    }

    func testNextSpeciesAvoidsCurrentWhenAllGraduated() {
        let ids = ["a", "b"]
        var rng = SeededRNG(seed: 3)
        // 全部毕业 → 无未养过者，回退「避开当前」→ 只能是非当前 a
        let pick = PetSelection.nextSpecies(
            available: ids, graduated: ["a", "b"], current: "b", using: &rng)
        XCTAssertEqual(pick, "a")
    }

    func testNextSpeciesFallsBackWhenOnlyCurrentAvailable() {
        var rng = SeededRNG(seed: 5)
        // 唯一物种即当前且已毕业 → 最终回退全体随机，仍返回它
        let pick = PetSelection.nextSpecies(
            available: ["a"], graduated: ["a"], current: "a", using: &rng)
        XCTAssertEqual(pick, "a")
    }

    func testNextSpeciesEmptyReturnsNil() {
        var rng = SeededRNG(seed: 1)
        XCTAssertNil(
            PetSelection.nextSpecies(available: [], graduated: [], current: nil, using: &rng))
    }
}
