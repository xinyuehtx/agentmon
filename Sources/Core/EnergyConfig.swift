import Foundation

/// 能量速率与进化门槛（可配置、可持久化）。契约见 specs/agent-task-monitor.md §3。
public struct EnergyConfig: Codable, Equatable {
    public var workingPerMin: Double  // 每个工作中任务 / 分钟
    public var waitingPerMin: Double  // 每个等待中任务 / 分钟（通常为负）
    public var completedBonus: Double  // 每次完成一次性加成
    public var idleDecayPerMin: Double  // 无任务时 / 分钟（通常为负）
    public var thresholds: [Double]  // thresholds[i] = 从 level (i+1) 升到 (i+2) 所需能量

    public init(
        workingPerMin: Double,
        waitingPerMin: Double,
        completedBonus: Double,
        idleDecayPerMin: Double,
        thresholds: [Double]
    ) {
        self.workingPerMin = workingPerMin
        self.waitingPerMin = waitingPerMin
        self.completedBonus = completedBonus
        self.idleDecayPerMin = idleDecayPerMin
        self.thresholds = thresholds
    }

    public static let `default` = EnergyConfig(
        workingPerMin: 2,
        waitingPerMin: -1,
        completedBonus: 30,
        idleDecayPerMin: -0.5,
        thresholds: [300, 900, 2000]
    )
}
