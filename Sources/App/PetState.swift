import Combine
import SwiftUI
import agentmonCore

/// 宠物的可观察状态，驱动 PetView 表现。
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
    /// 当前正在播放的动作变体（由 AppDelegate 在状态变化时随机挑选）。
    @Published var variant: PetVariant?
    @Published var variantStart: Date = Date()
}
