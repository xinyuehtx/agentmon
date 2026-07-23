import Foundation

/// 宠物「矢量木偶」+ 关键帧/粒子动画模型（对应 assets/pets.json schemaVersion 2）。

public struct PetKeyframe: Codable, Equatable {
    public var t: Double
    public var dx: Double
    public var dy: Double
    public var sx: Double
    public var sy: Double
    public var rot: Double
    public var a: Double
    public var ease: String?  // linear|in|out|inout|back|elastic（nil → inout）
}

public struct PetPart: Codable, Equatable {
    public var name: String
    public var kind: String  // "ellipse" | "poly"
    public var cx: Double
    public var cy: Double
    public var rx: Double
    public var ry: Double
    public var rot: Double
    public var points: [[Double]]?
    public var fill: String
    public var stroke: String?
    public var strokeW: Double
}

public struct PetEmitter: Codable, Equatable {
    public var kind: String
    public var t0: Double
    public var t1: Double
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var gravity: Double
    public var count: Int
    public var life: Double
    public var size: Double
    public var color: String
}

public struct PetVariant: Codable, Equatable {
    public var id: String
    public var dur: Double
    public var loop: Bool
    public var root: [PetKeyframe]
    public var tracks: [String: [PetKeyframe]]
    public var emitters: [PetEmitter]
}

public struct PetStage: Codable, Equatable {
    public var stage: String
    public var viewBox: Double
    public var parts: [PetPart]
    public var states: [String: [PetVariant]]
}

public struct PetSpecies: Codable, Equatable {
    public var id: String
    public var name: String
    public var element: String
    public var palette: [String: String]
    public var stages: [PetStage]

    public func stage(_ name: String) -> PetStage? { stages.first { $0.stage == name } }
}

public struct PetCatalog: Codable, Equatable {
    public var schemaVersion: Int
    public var species: [PetSpecies]

    public init(schemaVersion: Int, species: [PetSpecies]) {
        self.schemaVersion = schemaVersion
        self.species = species
    }

    public func species(id: String) -> PetSpecies? { species.first { $0.id == id } }
    public var speciesIDs: [String] { species.map(\.id) }
}

public enum PetLibrary {
    public static func decode(_ data: Data) throws -> PetCatalog {
        try JSONDecoder().decode(PetCatalog.self, from: data)
    }
    public static func load(from url: URL) throws -> PetCatalog {
        try decode(try Data(contentsOf: url))
    }
}
