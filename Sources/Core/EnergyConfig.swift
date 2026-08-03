import Foundation

/// 能量速率与进化门槛（可配置、可持久化）。契约见 specs/agent-task-monitor.md §3。
public struct EnergyConfig: Codable, Equatable {
    public var workingPerMin: Double  // 每个工作中任务 / 分钟
    public var waitingPerMin: Double  // 每个等待中任务 / 分钟（通常为负）
    public var completedBonus: Double  // 每次完成一次性加成
    public var idleDecayPerMin: Double  // 无任务时 / 分钟（通常为负）
    public var thresholds: [Double]  // thresholds[i] = 从 level (i+1) 升到 (i+2) 所需能量
    /// 毕业封顶等级：level 到达此值即封顶（成长停止=最终形态）。
    /// 默认 4 = 引擎 level 1..4 → 显示 Lv0..Lv3（蛋/幼年/青年/成熟，见 PetProgression）。
    public var graduationLevel: Int
    /// 饥饿死亡阈值：能量归零后持续空闲累计分钟达此值即「饿死」重生。默认 4320 = 3 天。
    public var starveDeathMinutes: Double

    public init(
        workingPerMin: Double,
        waitingPerMin: Double,
        completedBonus: Double,
        idleDecayPerMin: Double,
        thresholds: [Double],
        graduationLevel: Int = 4,
        starveDeathMinutes: Double = 4320
    ) {
        self.workingPerMin = workingPerMin
        self.waitingPerMin = waitingPerMin
        self.completedBonus = completedBonus
        self.idleDecayPerMin = idleDecayPerMin
        self.thresholds = thresholds
        self.graduationLevel = graduationLevel
        self.starveDeathMinutes = starveDeathMinutes
    }

    /// 向后兼容解码：旧 config.json 无 graduationLevel/starveDeathMinutes 字段时用默认值，
    /// 不丢用户已调的速率/门槛。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workingPerMin = try c.decode(Double.self, forKey: .workingPerMin)
        waitingPerMin = try c.decode(Double.self, forKey: .waitingPerMin)
        completedBonus = try c.decode(Double.self, forKey: .completedBonus)
        idleDecayPerMin = try c.decode(Double.self, forKey: .idleDecayPerMin)
        thresholds = try c.decode([Double].self, forKey: .thresholds)
        graduationLevel = try c.decodeIfPresent(Int.self, forKey: .graduationLevel) ?? 4
        starveDeathMinutes = try c.decodeIfPresent(Double.self, forKey: .starveDeathMinutes) ?? 4320
    }

    public static let `default` = EnergyConfig(
        workingPerMin: 2,
        waitingPerMin: -1,
        completedBonus: 30,
        idleDecayPerMin: -0.5,
        thresholds: [100, 250, 500]  // Lv0→1→2→3（蛋→幼年→青年→成熟），累计≈850，约 3 天活跃到成熟
    )
}
