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
}
