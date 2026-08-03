import XCTest

@testable import agentmonCore

/// 单元测试：能量累积 / 消耗 / 完成加成 / 空闲衰减 / 能量下限 / 进化 / 多级跳 / 不回退 / 门槛函数。
/// 契约见 specs/agent-task-monitor.md §3, §4。所有时间由入参驱动，保证确定性。
final class EnergyEngineTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 0)
    /// t0 之后 `minutes` 分钟的时刻
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    /// 引擎机制测试用固定 config（与默认值解耦：默认门槛/封顶已改为 Lv0–Lv5 6 档，
    /// 这些用例只验证引擎数学，故用显式已知门槛 [300,900,2000]/封顶 5）。
    private static let testConfig = EnergyConfig(
        workingPerMin: 2, waitingPerMin: -1, completedBonus: 30, idleDecayPerMin: -0.5,
        thresholds: [300, 900, 2000], graduationLevel: 5)

    private func makeEngine(
        energy: Double = 0,
        level: Int = 1,
        config: EnergyConfig = EnergyEngineTests.testConfig
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

    // MARK: - 毕业封顶 / 饥饿 / 重生

    private func starveConfig(_ deathMinutes: Double) -> EnergyConfig {
        EnergyConfig(
            workingPerMin: 2, waitingPerMin: -1, completedBonus: 30, idleDecayPerMin: -0.5,
            thresholds: [300, 900, 2000], graduationLevel: 5, starveDeathMinutes: deathMinutes)
    }

    func testGraduationCapAndFreeze() {
        // level 4（final）再攒满一档(4000) → level 5 毕业封顶
        let e = makeEngine(energy: 3990, level: 4)
        var graduated = 0
        e.onGraduate = { graduated += 1 }
        e.registerCompletions(1, now: t0)  // 3990 + 30 = 4020 >= 4000
        XCTAssertEqual(e.level, 5)
        XCTAssertTrue(e.isGraduated)
        XCTAssertEqual(e.energy, 0, accuracy: 1e-6)  // 封顶后能量清零
        XCTAssertEqual(graduated, 1)

        // 封顶后冻结：即便工作也不再涨、不再触发毕业
        e.tick(now: at(100), workingCount: 3, waitingCount: 0)
        XCTAssertEqual(e.level, 5)
        XCTAssertEqual(e.energy, 0, accuracy: 1e-6)
        XCTAssertEqual(graduated, 1)
    }

    func testStarvationAccrualAndSignal() {
        let e = EnergyEngine(config: starveConfig(100), energy: 0, level: 1, lastTick: t0)
        var starved = 0
        e.onStarve = { starved += 1 }
        e.tick(now: at(60), workingCount: 0, waitingCount: 0)  // 能量已 0 且空闲
        XCTAssertEqual(e.starveMinutes, 60, accuracy: 1e-6)
        XCTAssertEqual(starved, 0)
        e.tick(now: at(110), workingCount: 0, waitingCount: 0)  // 累计 110 >= 100
        XCTAssertEqual(starved, 1)
        // 越阈后不重复触发
        e.tick(now: at(160), workingCount: 0, waitingCount: 0)
        XCTAssertEqual(starved, 1)
    }

    func testStarvationResetsOnActivity() {
        let e = EnergyEngine(config: starveConfig(100), energy: 0, level: 1, lastTick: t0)
        e.tick(now: at(60), workingCount: 0, waitingCount: 0)
        XCTAssertEqual(e.starveMinutes, 60, accuracy: 1e-6)
        e.tick(now: at(70), workingCount: 1, waitingCount: 0)  // 有活动 → 清零
        XCTAssertEqual(e.starveMinutes, 0, accuracy: 1e-6)
    }

    func testOfflineDecayAccruesStarvation() {
        // energy 30, -0.5/min → 60min 触底；离线 200min → 停留 0 的 140min 计入饥饿
        let e = EnergyEngine(config: starveConfig(100), energy: 30, level: 1, lastTick: t0)
        e.applyOfflineDecay(now: at(200))
        XCTAssertEqual(e.energy, 0, accuracy: 1e-6)
        XCTAssertEqual(e.starveMinutes, 140, accuracy: 1e-6)
    }

    func testRebirthResets() {
        let e = makeEngine(energy: 500, level: 3)
        e.rebirth(now: at(10))
        XCTAssertEqual(e.level, 1)
        XCTAssertEqual(e.energy, 0, accuracy: 1e-6)
        XCTAssertEqual(e.starveMinutes, 0, accuracy: 1e-6)
    }

    func testSuspendPausesAccrual() {
        let e = makeEngine(energy: 100, level: 2)
        e.suspend(now: at(1000))  // 只推进 lastTick，不结算
        XCTAssertEqual(e.energy, 100, accuracy: 1e-6)
        e.tick(now: at(1000), workingCount: 0, waitingCount: 0)  // elapsed=0
        XCTAssertEqual(e.energy, 100, accuracy: 1e-6)
    }

    func testDefaultConfigIsFourTierLv0to3() {
        // 默认 Lv0–Lv3（蛋/幼年/青年/成熟）：封顶 4、3 档门槛（累计约 3 天到成熟）
        XCTAssertEqual(EnergyConfig.default.graduationLevel, 4)
        XCTAssertEqual(EnergyConfig.default.thresholds, [100, 250, 500])
    }
}
