import XCTest

@testable import agentmonCore

/// 单元测试：能量累积 / 消耗 / 完成加成 / 空闲衰减 / 能量下限 / 进化 / 多级跳 / 不回退 / 门槛函数。
/// 契约见 specs/agent-task-monitor.md §3, §4。所有时间由入参驱动，保证确定性。
final class EnergyEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    /// t0 之后 `minutes` 分钟的时刻
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private func makeEngine(
        energy: Double = 0,
        level: Int = 1,
        config: EnergyConfig = .default
    ) -> EnergyEngine {
        EnergyEngine(config: config, energy: energy, level: level, lastTick: t0)
    }

    // US-B1
    func testWorkingAccrual() {
        let e = makeEngine()
        e.tick(now: at(10), workingCount: 1, waitingCount: 0)
        XCTAssertEqual(e.energy, 20, accuracy: 1e-6)  // +2 * 1 * 10min
        XCTAssertEqual(e.level, 1)
    }

    // US-B2
    func testWaitingPenalty() {
        let e = makeEngine(energy: 50)
        e.tick(now: at(10), workingCount: 0, waitingCount: 2)
        XCTAssertEqual(e.energy, 30, accuracy: 1e-6)  // -1 * 2 * 10min
    }

    func testMixedWorkingAndWaiting() {
        let e = makeEngine()
        e.tick(now: at(10), workingCount: 2, waitingCount: 1)
        XCTAssertEqual(e.energy, 30, accuracy: 1e-6)  // (2*2 + (-1)*1) * 10
    }

    // US-B4
    func testIdleDecayWhenNoTasks() {
        let e = makeEngine(energy: 50)
        e.tick(now: at(10), workingCount: 0, waitingCount: 0)
        XCTAssertEqual(e.energy, 45, accuracy: 1e-6)  // -0.5 * 10
    }

    // US-B5
    func testEnergyFloorAtZero() {
        let e = makeEngine(energy: 3)
        e.tick(now: at(10), workingCount: 0, waitingCount: 0)  // would be -5
        XCTAssertEqual(e.energy, 0, accuracy: 1e-6)
    }

    // US-B3
    func testCompletionBonus() {
        let e = makeEngine(energy: 10)
        e.registerCompletions(2, now: t0)
        XCTAssertEqual(e.energy, 70, accuracy: 1e-6)  // +30 * 2
    }

    // US-B6
    func testEvolutionSingleLevel() {
        let e = makeEngine(energy: 290, level: 1)
        var evolved: [Int] = []
        e.onEvolve = { evolved.append($0.newLevel) }
        e.registerCompletions(1, now: t0)  // 290 + 30 = 320 >= 300
        XCTAssertEqual(e.level, 2)
        XCTAssertEqual(e.energy, 20, accuracy: 1e-6)  // 320 - 300 结转
        XCTAssertEqual(evolved, [2])
    }

    // US-B8
    func testEvolutionMultiLevelJump() {
        let e = makeEngine(energy: 0, level: 1)
        var evolved: [Int] = []
        e.onEvolve = { evolved.append($0.newLevel) }
        // 一次 tick 净增 1300：+2 * 1 * 650min
        e.tick(now: at(650), workingCount: 1, waitingCount: 0)
        // 1300 -300-> L2(1000) -900-> L3(100); 100 < 2000 停
        XCTAssertEqual(e.level, 3)
        XCTAssertEqual(e.energy, 100, accuracy: 1e-6)
        XCTAssertEqual(evolved, [2, 3])
    }

    // US-B7
    func testLevelIsMonotonicNoRegress() {
        let e = makeEngine(energy: 290, level: 1)
        e.registerCompletions(1, now: t0)  // -> level 2, energy 20
        XCTAssertEqual(e.level, 2)
        e.tick(now: at(1000), workingCount: 0, waitingCount: 0)  // 巨量空闲衰减
        XCTAssertEqual(e.energy, 0, accuracy: 1e-6)
        XCTAssertEqual(e.level, 2)  // 不回退到 1
    }

    // US-B9
    func testOfflineDecay() {
        let e = makeEngine(energy: 100, level: 2)
        e.applyOfflineDecay(now: at(60))  // -0.5 * 60 = -30
        XCTAssertEqual(e.energy, 70, accuracy: 1e-6)
        XCTAssertEqual(e.level, 2)
    }

    func testThresholdBeyondConfigured() {
        let e = makeEngine()
        XCTAssertEqual(e.threshold(forLevel: 1), 300, accuracy: 1e-6)
        XCTAssertEqual(e.threshold(forLevel: 2), 900, accuracy: 1e-6)
        XCTAssertEqual(e.threshold(forLevel: 3), 2000, accuracy: 1e-6)
        XCTAssertEqual(e.threshold(forLevel: 4), 4000, accuracy: 1e-6)  // last * 2
    }

    func testNoTimeTravelOnStaleNow() {
        // now 早于 lastTick 时 elapsed 截断为 0，不产生负向穿越
        let e = makeEngine(energy: 50)
        e.tick(now: t0.addingTimeInterval(-600), workingCount: 1, waitingCount: 0)
        XCTAssertEqual(e.energy, 50, accuracy: 1e-6)
    }
}
