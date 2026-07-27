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

    /// 挑选下一只宠物的物种（重生 / 主动孵化）：
    /// 优先没养过（未毕业收藏）且非当前的物种；集齐后再避开当前随机；再退回全体随机。
    public static func nextSpecies<R: RandomNumberGenerator>(
        available: [String], graduated: [String], current: String?, using rng: inout R
    ) -> String? {
        let fresh = available.filter { !graduated.contains($0) && $0 != current }
        if let pick = fresh.randomElement(using: &rng) { return pick }
        let notCurrent = available.filter { $0 != current }
        if let pick = notCurrent.randomElement(using: &rng) { return pick }
        return available.randomElement(using: &rng)
    }
}
