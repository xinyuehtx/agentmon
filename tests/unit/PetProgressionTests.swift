import XCTest

@testable import agentmonCore

/// Lv0–Lv3 等级=形态进度，及「每级解锁更多动作」的映射。
final class PetProgressionTests: XCTestCase {

    func testDisplayLevelMapping() {
        XCTAssertEqual(PetProgression.displayLevel(engineLevel: 1), 0)
        XCTAssertEqual(PetProgression.displayLevel(engineLevel: 4), 3)
        XCTAssertEqual(PetProgression.displayLevel(engineLevel: 5), 3)  // 封顶
        XCTAssertEqual(PetProgression.displayLevel(engineLevel: 0), 0)  // 下限
        XCTAssertEqual(PetProgression.maxLevel, 3)
    }

    func testStageIndex1to1() {
        // 等级与 4 形态 1:1；超出封顶到最后一档
        XCTAssertEqual(PetProgression.stageIndex(displayLevel: 0, stageCount: 4), 0)
        XCTAssertEqual(PetProgression.stageIndex(displayLevel: 1, stageCount: 4), 1)
        XCTAssertEqual(PetProgression.stageIndex(displayLevel: 2, stageCount: 4), 2)
        XCTAssertEqual(PetProgression.stageIndex(displayLevel: 3, stageCount: 4), 3)
        XCTAssertEqual(PetProgression.stageIndex(displayLevel: 3, stageCount: 3), 2)  // 形态少于等级
        XCTAssertEqual(PetProgression.stageIndex(displayLevel: 0, stageCount: 0), 0)  // 无形态兜底
    }

    func testAmbientPoolGrowsMonotonically() {
        var prev = 0
        for lv in 0...PetProgression.maxLevel {
            let count = PetProgression.ambientActions(displayLevel: lv).count
            XCTAssertGreaterThanOrEqual(count, prev, "Lv\(lv) 解锁数不应减少")
            prev = count
        }
        XCTAssertEqual(PetProgression.ambientActions(displayLevel: 0), [])
        XCTAssertEqual(PetProgression.ambientActions(displayLevel: 1), ["jump"])
        XCTAssertEqual(PetProgression.ambientActions(displayLevel: 2), ["jump", "skill"])
        XCTAssertEqual(PetProgression.ambientActions(displayLevel: 3), ["jump", "skill", "complete"])
    }

    func testNewlyUnlockedAndNextUnlock() {
        XCTAssertNil(PetProgression.newlyUnlocked(displayLevel: 0))
        XCTAssertEqual(PetProgression.newlyUnlocked(displayLevel: 1), "jump")
        XCTAssertEqual(PetProgression.newlyUnlocked(displayLevel: 2), "skill")
        XCTAssertEqual(PetProgression.newlyUnlocked(displayLevel: 3), "complete")

        XCTAssertEqual(PetProgression.nextUnlock(displayLevel: 0), "jump")
        XCTAssertEqual(PetProgression.nextUnlock(displayLevel: 2), "complete")
        XCTAssertNil(PetProgression.nextUnlock(displayLevel: 3))  // 已满级
    }

    func testNames() {
        XCTAssertEqual(PetProgression.actionName("jump"), "跳跃")
        XCTAssertEqual(PetProgression.actionName("complete"), "撒花")
        XCTAssertEqual(PetProgression.stageName("egg"), "幼年·蛋")
        XCTAssertEqual(PetProgression.stageName("mature"), "成熟")
        XCTAssertLessThan(
            PetProgression.ambientCooldown(displayLevel: 3),
            PetProgression.ambientCooldown(displayLevel: 1))
    }
}
