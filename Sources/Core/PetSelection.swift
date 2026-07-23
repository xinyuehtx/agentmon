import Foundation

/// 宠物随机分配与阶段映射。
public enum PetSelection {
    /// 进化阶段顺序（对应 EnergyEngine.level：1→egg, 2→juvenile, 3→mature, ≥4→final）。
    public static let stageOrder = ["egg", "juvenile", "mature", "final"]

    public static func stage(forLevel level: Int) -> String {
        let index = max(1, level) - 1
        return stageOrder[min(index, stageOrder.count - 1)]
    }

    /// 从候选物种中随机选一个（注入 RNG 便于测试确定性）。
    public static func choose<R: RandomNumberGenerator>(
        speciesIDs ids: [String], using rng: inout R
    ) -> String? {
        ids.randomElement(using: &rng)
    }
}
