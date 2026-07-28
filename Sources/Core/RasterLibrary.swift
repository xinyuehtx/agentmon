import Foundation

/// 光栅精灵图集清单（对应 assets/pets_raster/manifest.json，由 scripts/process-aurora.py 生成）。
/// v2：单角色（极光罗盘猫）共享一套动作动画（每动作一张横排透明「条」）+ 12 元素静态立绘收藏。

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

public struct RasterManifest: Codable, Equatable {
    public var schemaVersion: Int
    public var character: String
    public var frameHeight: Int
    public var actions: [String: RasterAction]  // idle/working/waiting/complete/evolve/hungry/jump/skill
    public var elements: [RasterElement]

    public init(
        schemaVersion: Int, character: String, frameHeight: Int,
        actions: [String: RasterAction], elements: [RasterElement]
    ) {
        self.schemaVersion = schemaVersion
        self.character = character
        self.frameHeight = frameHeight
        self.actions = actions
        self.elements = elements
    }

    public func action(_ key: String) -> RasterAction? { actions[key] }
    public func element(id: String) -> RasterElement? { elements.first { $0.id == id } }
    public var elementIDs: [String] { elements.map(\.id) }
}

public enum RasterLibrary {
    public static func decode(_ data: Data) throws -> RasterManifest {
        try JSONDecoder().decode(RasterManifest.self, from: data)
    }
    public static func load(from url: URL) throws -> RasterManifest {
        try decode(try Data(contentsOf: url))
    }
}
