import XCTest

@testable import agentmonCore

/// 校验实际生成的 assets/pets.json（schemaVersion 2：矢量部件 + 关键帧/粒子动画）。
final class PetLibraryTests: XCTestCase {

    private func loadCatalog() throws -> PetCatalog {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/pets.json")
        return try PetLibrary.load(from: url)
    }

    func testCatalogShape() throws {
        let cat = try loadCatalog()
        XCTAssertEqual(cat.schemaVersion, 2)
        XCTAssertEqual(cat.speciesIDs.sorted(), ["aqua", "ember", "sprout"])
        for sp in cat.species {
            XCTAssertFalse(sp.palette.isEmpty)
            XCTAssertEqual(sp.stages.map(\.stage), ["egg", "juvenile", "mature", "final"])
            for st in sp.stages {
                XCTAssertFalse(st.parts.isEmpty, "\(sp.id)/\(st.stage) 无部件")
                XCTAssertGreaterThan(st.viewBox, 0)
                for key in ["idle", "working", "waiting", "complete"] {
                    XCTAssertFalse(st.states[key]?.isEmpty ?? true, "\(sp.id)/\(st.stage) 缺状态 \(key)")
                }
                for v in st.states["complete"] ?? [] {
                    XCTAssertFalse(v.loop, "complete 变体应为一次性")
                }
            }
        }
    }

    func testVariantTracksReferenceRealParts() throws {
        let cat = try loadCatalog()
        for sp in cat.species {
            for st in sp.stages {
                let partNames = Set(st.parts.map(\.name))
                for (_, variants) in st.states {
                    for v in variants {
                        XCTAssertFalse(v.root.isEmpty, "\(sp.id)/\(st.stage)/\(v.id) root 空")
                        for name in v.tracks.keys {
                            XCTAssertTrue(partNames.contains(name), "\(sp.id)/\(st.stage)/\(v.id) 轨道引用未知部件 \(name)")
                        }
                        for e in v.emitters {
                            XCTAssertGreaterThan(e.count, 0)
                        }
                    }
                }
            }
        }
    }

    func testMultipleVariantsPerAttack() throws {
        let cat = try loadCatalog()
        // 非蛋阶段的 working / idle 应有多个可随机变体
        let juv = cat.species(id: "aqua")!.stage("juvenile")!
        XCTAssertGreaterThan(juv.states["working"]!.count, 1)  // 水枪/泡泡
        XCTAssertGreaterThan(juv.states["idle"]!.count, 1)
    }

    func testFillKeysAreInPalette() throws {
        let cat = try loadCatalog()
        for sp in cat.species {
            for st in sp.stages {
                for part in st.parts {
                    XCTAssertNotNil(sp.palette[part.fill], "\(sp.id) 部件 \(part.name) 缺填充色 \(part.fill)")
                }
            }
        }
    }
}
