import Combine
import SwiftUI

/// 宠物的可观察状态，驱动 RasterPetView 表现。
final class PetState: ObservableObject {
    enum Mood { case idle, working, waiting, celebrate, evolve }

    @Published var mood: Mood = .idle
    @Published var level: Int = 1
    @Published var energy: Double = 0
    @Published var energyToNext: Double = 300
    @Published var working: Int = 0
    @Published var waiting: Int = 0
    @Published var completed: Int = 0
    @Published var species: String = "sprout"
    @Published var stage: String = "egg"
    /// 是否处于收藏皮肤展示模式（成长暂停）；面板标签据此显示「收藏 · 形态」而非 Lv。
    @Published var isSkin: Bool = false
    /// 当前动作动画的播放起点（状态/阶段变化时重置；用于循环与一次性 complete 计时）。
    @Published var variantStart: Date = Date()
}
