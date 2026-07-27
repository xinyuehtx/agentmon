import Foundation

/// 能量与进化引擎。契约见 specs/agent-task-monitor.md §4。
///
/// 设计不变量：
/// - `energy >= 0` 恒成立（截断到 0）；
/// - 单生命内 `level` 单调不回退（`rebirth` 是显式的生命重置，不算回退）；
/// - `level` 封顶在 `config.graduationLevel`（到达即毕业、成长停止）；
/// - 纯确定性：所有时间由入参 `now` 驱动，内部不调用 `Date()`。
public final class EnergyEngine {

    public private(set) var energy: Double
    public private(set) var level: Int
    /// 能量归零后持续空闲累计分钟数（有活动/能量>0 即清零）。达 `config.starveDeathMinutes` 触发 `onStarve`。
    public private(set) var starveMinutes: Double
    public let config: EnergyConfig
    public var onEvolve: ((EvolutionEvent) -> Void)?
    /// level 升到 `config.graduationLevel`（封顶/毕业）时触发一次。
    public var onGraduate: (() -> Void)?
    /// `starveMinutes` 越过 `config.starveDeathMinutes` 时触发一次。
    public var onStarve: (() -> Void)?

    private var lastTick: Date
    private var starveFired = false

    public init(
        config: EnergyConfig = .default,
        energy: Double = 0,
        level: Int = 1,
        starveMinutes: Double = 0,
        lastTick: Date
    ) {
        self.config = config
        self.energy = energy
        self.level = level
        self.starveMinutes = starveMinutes
        self.lastTick = lastTick
    }

    /// 是否已毕业封顶（成长停止、解锁为永久皮肤）。
    public var isGraduated: Bool { level >= config.graduationLevel }

    private func elapsedMinutes(to now: Date) -> Double {
        max(0, now.timeIntervalSince(lastTick) / 60)
    }

    /// 时间推进结算：有活跃任务时按速率累积，否则按空闲衰减。封顶后冻结。
    public func tick(now: Date, workingCount: Int, waitingCount: Int) {
        let minutes = elapsedMinutes(to: now)
        lastTick = now
        guard !isGraduated else { return }  // 已毕业：冻结，不成长/不衰减/不饥饿

        let idle = workingCount == 0 && waitingCount == 0
        let delta: Double
        if !idle {
            delta =
                (config.workingPerMin * Double(workingCount)
                    + config.waitingPerMin * Double(waitingCount)) * minutes
        } else {
            delta = config.idleDecayPerMin * minutes
        }
        energy = max(0, energy + delta)
        checkEvolution()

        // 饥饿计时：能量归零且完全空闲才累计，否则清零。
        if energy == 0 && idle {
            starveMinutes += minutes
        } else {
            starveMinutes = 0
            starveFired = false
        }
        checkStarve()
    }

    /// 完成任务的一次性加成（不改变 lastTick）。视为活动 → 清空饥饿计时。
    public func registerCompletions(_ count: Int, now: Date) {
        guard count > 0 else { return }
        energy = max(0, energy + config.completedBonus * Double(count))
        starveMinutes = 0
        starveFired = false
        checkEvolution()
    }

    /// 离线期间仅施加空闲衰减（重启恢复用）。
    /// 估算离线期停留在 0 的分钟数累加到饥饿计时；不在此触发 `onStarve`（回调尚未接线），
    /// 交由启动后首个 `tick` 判定（用户回来活动则自然清零，宠物存活）。
    public func applyOfflineDecay(now: Date) {
        let minutes = elapsedMinutes(to: now)
        lastTick = now
        guard !isGraduated else { return }

        let decayPerMin = -config.idleDecayPerMin  // 通常为正
        let minutesToZero = decayPerMin > 0 ? energy / decayPerMin : .greatestFiniteMagnitude
        energy = max(0, energy + config.idleDecayPerMin * minutes)
        if energy == 0 {
            starveMinutes += max(0, minutes - minutesToZero)
        } else {
            starveMinutes = 0
            starveFired = false
        }
    }

    /// 生命重置：换新蛋（饿死重生 / 主动孵化）。物种由编排层更换。
    public func rebirth(now: Date) {
        energy = 0
        level = 1
        starveMinutes = 0
        starveFired = false
        lastTick = now
    }

    /// 暂停成长：仅推进 lastTick，不结算能量/饥饿（展示收藏皮肤期间用，避免恢复时补算大额 delta）。
    public func suspend(now: Date) {
        lastTick = now
    }

    private func checkStarve() {
        if !starveFired && starveMinutes >= config.starveDeathMinutes {
            starveFired = true
            onStarve?()
        }
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
        while level < config.graduationLevel && energy >= threshold(forLevel: level) {
            energy -= threshold(forLevel: level)
            level += 1
            onEvolve?(EvolutionEvent(newLevel: level))
            if level >= config.graduationLevel {
                energy = 0  // 封顶后能量清零，展示为满级毕业态
                onGraduate?()
            }
        }
    }
}
