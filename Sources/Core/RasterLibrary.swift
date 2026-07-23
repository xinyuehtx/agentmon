import Foundation

/// 光栅精灵图集清单（对应 assets/pets_raster/manifest.json，由 scripts/process-packs.swift 生成）。
/// 每个动作 = 一张紧凑透明「条」PNG（横排 `frames` 帧，每帧 `fw`×`fh`）。

public struct RasterAction: Codable, Equatable {
    public var file: String  // 相对 manifest 目录
    public var frames: Int
    public var fw: Int
    public var fh: Int
    public var fps: Int
}

public struct RasterStage: Codable, Equatable {
    public var stage: String
    public var actions: [String: RasterAction]  // idle/working/waiting/complete
}

public struct RasterSpecies: Codable, Equatable {
    public var id: String
    public var element: String
    public var stages: [RasterStage]

    public func stage(_ name: String) -> RasterStage? { stages.first { $0.stage == name } }
}

public struct RasterManifest: Codable, Equatable {
    public var schemaVersion: Int
    public var frameHeight: Int
    public var species: [RasterSpecies]

    public init(schemaVersion: Int, frameHeight: Int, species: [RasterSpecies]) {
        self.schemaVersion = schemaVersion
        self.frameHeight = frameHeight
        self.species = species
    }

    public func species(id: String) -> RasterSpecies? { species.first { $0.id == id } }
    public var speciesIDs: [String] { species.map(\.id) }
}

public enum RasterLibrary {
    public static func decode(_ data: Data) throws -> RasterManifest {
        try JSONDecoder().decode(RasterManifest.self, from: data)
    }
    public static func load(from url: URL) throws -> RasterManifest {
        try decode(try Data(contentsOf: url))
    }
}
