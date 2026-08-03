import Foundation

/// 桌宠等级进度：Lv0–Lv3，等级即成长形态（蛋→幼年→青年→成熟），升级即进化。
/// 每级另解锁更多「随机表现动作」（仿 DyberPet favor 门控 random_act）；
/// 核心状态动作 idle/working/waiting/complete/hungry 恒可用，不在解锁池内。
/// 契约见 specs/agent-task-monitor.md §3、§8。
public enum PetProgression {
    /// 最高显示等级（Lv0..maxLevel）。引擎 level 1..(maxLevel+1) 映射到此。
    public static let maxLevel = 3

    /// 引擎 level（从 1 起）→ 显示等级 Lv（0..maxLevel）。
    public static func displayLevel(engineLevel: Int) -> Int {
        max(0, min(maxLevel, engineLevel - 1))
    }

    /// 显示等级 → 成长形态下标（等级与形态 1:1；形态数不足时封顶到最后一档）。
    public static func stageIndex(displayLevel lv: Int, stageCount: Int) -> Int {
        guard stageCount > 0 else { return 0 }
        return max(0, min(stageCount - 1, lv))
    }

    /// 该显示等级解锁的随机表现动作池（越高级越多）。
    public static func ambientActions(displayLevel lv: Int) -> [String] {
        let l = max(0, min(maxLevel, lv))
        var pool: [String] = []
        if l >= 1 { pool.append("jump") }
        if l >= 2 { pool.append("skill") }
        if l >= 3 { pool.append("complete") }  // cheer 撒花
        return pool
    }

    /// 该级相对上一级「新解锁」的动作（Lv0 与已满级返回 nil），供 UI 展示。
    public static func newlyUnlocked(displayLevel lv: Int) -> String? {
        let cur = ambientActions(displayLevel: lv)
        let prev = ambientActions(displayLevel: lv - 1)
        return cur.count > prev.count ? cur.last : nil
    }

    /// 升到下一级会新解锁的动作（已满级返回 nil），供「下一级解锁：X」。
    public static func nextUnlock(displayLevel lv: Int) -> String? {
        lv >= maxLevel ? nil : newlyUnlocked(displayLevel: lv + 1)
    }

    /// 动作 id → 中文名（UI 展示）。
    public static func actionName(_ key: String) -> String {
        [
            "idle": "发呆", "working": "干活", "waiting": "打盹", "complete": "撒花",
            "evolve": "进化", "hungry": "饿了", "jump": "跳跃", "skill": "技能",
        ][key] ?? key
    }

    /// 成长形态 id → 中文名（UI 展示）。
    public static func stageName(_ stage: String) -> String {
        [
            "egg": "幼年·蛋", "baby": "幼体", "youth": "青年", "mature": "成熟",
            // 兼容旧 aurora 命名
            "juvenile": "幼年", "final": "成年",
        ][stage] ?? stage
    }

    /// 空闲时随机表现动作的冷却秒数（越高级越频繁）。
    public static func ambientCooldown(displayLevel lv: Int) -> Double {
        Double(max(4, 14 - 2 * max(0, min(maxLevel, lv))))
    }
}
