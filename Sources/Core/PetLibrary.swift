import Foundation

/// 宠物动画数据模型（对应 assets/pets.json，由 scripts/make-pets.swift 生成）。
public struct PetAnimation: Codable, Equatable {
    public let fps: Int
    public let loop: Bool
    public let frames: [[String]]  // 每帧 = 行字符串数组；字符索引 palette，'.' 透明
}

public struct PetStage: Codable, Equatable {
    public let stage: String
    public let anims: [String: PetAnimation]
}

public struct PetSpecies: Codable, Equatable {
    public let id: String
    public let name: String
    public let element: String
    public let palette: [String: String]  // char -> hex
    public let stages: [PetStage]

    public func stage(_ name: String) -> PetStage? { stages.first { $0.stage == name } }
}

public struct PetCatalog: Codable, Equatable {
    public let schemaVersion: Int
    public let species: [PetSpecies]

    public init(schemaVersion: Int, species: [PetSpecies]) {
        self.schemaVersion = schemaVersion
        self.species = species
    }

    public func species(id: String) -> PetSpecies? { species.first { $0.id == id } }
    public var speciesIDs: [String] { species.map(\.id) }
}

/// 加载/解码宠物图鉴。
public enum PetLibrary {
    public static func decode(_ data: Data) throws -> PetCatalog {
        try JSONDecoder().decode(PetCatalog.self, from: data)
    }

    public static func load(from url: URL) throws -> PetCatalog {
        try decode(try Data(contentsOf: url))
    }
}
