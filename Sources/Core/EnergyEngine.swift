import Foundation

/// 能量与进化引擎。契约见 specs/agent-task-monitor.md §4。
///
/// 设计不变量：
/// - `energy >= 0` 恒成立（截断到 0）；
/// - `level` 单调不回退；
/// - 纯确定性：所有时间由入参 `now` 驱动，内部不调用 `Date()`。
public final class EnergyEngine {

    public private(set) var energy: Double
    public private(set) var level: Int
    public let config: EnergyConfig
    public var onEvolve: ((EvolutionEvent) -> Void)?

    private var lastTick: Date

    public init(
        config: EnergyConfig = .default,
        energy: Double = 0,
        level: Int = 1,
        lastTick: Date
    ) {
        self.config = config
        self.energy = energy
        self.level = level
        self.lastTick = lastTick
    }

    private func elapsedMinutes(to now: Date) -> Double {
        max(0, now.timeIntervalSince(lastTick) / 60)
    }

    /// 时间推进结算：有活跃任务时按速率累积，否则按空闲衰减。
    public func tick(now: Date, workingCount: Int, waitingCount: Int) {
        let minutes = elapsedMinutes(to: now)
        let delta: Double
        if workingCount > 0 || waitingCount > 0 {
            delta =
                (config.workingPerMin * Double(workingCount)
                    + config.waitingPerMin * Double(waitingCount)) * minutes
        } else {
            delta = config.idleDecayPerMin * minutes
        }
        energy = max(0, energy + delta)
        lastTick = now
        checkEvolution()
    }

    /// 完成任务的一次性加成（不改变 lastTick）。
    public func registerCompletions(_ count: Int, now: Date) {
        guard count > 0 else { return }
        energy = max(0, energy + config.completedBonus * Double(count))
        checkEvolution()
    }

    /// 离线期间仅施加空闲衰减（重启恢复用）。
    public func applyOfflineDecay(now: Date) {
        let minutes = elapsedMinutes(to: now)
        energy = max(0, energy + config.idleDecayPerMin * minutes)
        lastTick = now
    }

    /// 从 `level` 升到 `level+1` 所需门槛。超出配置范围时按最后一档 ×2 递推。
    public func threshold(forLevel level: Int) -> Double {
        let count = config.thresholds.count
        if level >= 1 && level <= count {
            return config.thresholds[level - 1]
        }
        guard let last = config.thresholds.last else { return .greatestFiniteMagnitude }
        let extra = level - count
        return last * pow(2, Double(extra))
    }

    private func checkEvolution() {
        while energy >= threshold(forLevel: level) {
            energy -= threshold(forLevel: level)
            level += 1
            onEvolve?(EvolutionEvent(newLevel: level))
        }
    }
}
