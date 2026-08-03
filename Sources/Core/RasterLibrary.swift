import Foundation

/// 光栅精灵图集清单（对应 assets/pets_raster/packs/<mon>/manifest.json，由 scripts/video_to_pack.py 生成）。
/// v2：单形态，一套动作动画（每动作一张横排透明「条」）+ 可选元素立绘；
/// v3：多形态（`stages:[{stage,actions}]`），按等级进化切换形态（如草系罗盘猫 verdant 的蛋/幼体/少年/成熟）。

public struct RasterAction: Codable, Equatable {
    public var file: String  // 相对 manifest 目录
    public var frames: Int
    public var fw: Int
    public var fh: Int
    public var fps: Int

    public init(file: String, frames: Int, fw: Int, fh: Int, fps: Int) {
        self.file = file
        self.frames = frames
        self.fw = fw
        self.fh = fh
        self.fps = fps
    }
}

/// 一个可收藏的元素变体（静态立绘 + 主题色）。
public struct RasterElement: Codable, Equatable {
    public var id: String
    public var name: String
    public var portrait: String  // 相对 manifest 目录
    public var tint: String  // 十六进制主题色，如 "#4AA3FF"

    public init(id: String, name: String, portrait: String, tint: String) {
        self.id = id
        self.name = name
        self.portrait = portrait
        self.tint = tint
    }
}

/// 一个成长形态（v3：多形态角色，如 verdant 的 egg/baby/youth/mature），各含整套动作条。
public struct RasterStage: Codable, Equatable {
    public var stage: String
    public var actions: [String: RasterAction]

    public init(stage: String, actions: [String: RasterAction]) {
        self.stage = stage
        self.actions = actions
    }
}

public struct RasterManifest: Codable, Equatable {
    public var schemaVersion: Int
    public var character: String
    public var frameHeight: Int
    public var actions: [String: RasterAction]  // v2 单形态：idle/working/…；v3 多形态时可空
    public var elements: [RasterElement]
    /// v3 可选：多形态角色的各形态动作（egg/baby/youth/mature…）。v2 为 nil。
    public var stages: [RasterStage]?
    /// 可选属性标签（如 "grass"）。
    public var element: String?

    public init(
        schemaVersion: Int, character: String, frameHeight: Int,
        actions: [String: RasterAction], elements: [RasterElement],
        stages: [RasterStage]? = nil, element: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.character = character
        self.frameHeight = frameHeight
        self.actions = actions
        self.elements = elements
        self.stages = stages
        self.element = element
    }

    /// 向后兼容解码：v2 无 stages/element，actions/elements 缺省即空（仿 EnergyConfig）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 2
        character = try c.decodeIfPresent(String.self, forKey: .character) ?? ""
        frameHeight = try c.decodeIfPresent(Int.self, forKey: .frameHeight) ?? 0
        actions = try c.decodeIfPresent([String: RasterAction].self, forKey: .actions) ?? [:]
        elements = try c.decodeIfPresent([RasterElement].self, forKey: .elements) ?? []
        stages = try c.decodeIfPresent([RasterStage].self, forKey: .stages)
        element = try c.decodeIfPresent(String.self, forKey: .element)
    }

    /// 某形态的动作表（无 stages 或未找到时回落到顶层 `actions`）。
    public func actions(forStage stage: String?) -> [String: RasterAction] {
        if let stage = stage, let s = stages?.first(where: { $0.stage == stage }) { return s.actions }
        return stages?.first?.actions ?? actions
    }

    /// 单形态便捷取动作（v2）；v3 取第一形态。
    public func action(_ key: String) -> RasterAction? { actions(forStage: nil)[key] }
    public func element(id: String) -> RasterElement? { elements.first { $0.id == id } }
    public var elementIDs: [String] { elements.map(\.id) }
    public var stageIDs: [String] { stages?.map(\.stage) ?? [] }
}

public enum RasterLibrary {
    public static func decode(_ data: Data) throws -> RasterManifest {
        try JSONDecoder().decode(RasterManifest.self, from: data)
    }
    public static func load(from url: URL) throws -> RasterManifest {
        try decode(try Data(contentsOf: url))
    }
}
