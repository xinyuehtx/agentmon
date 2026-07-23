import XCTest

@testable import agentmonCore

/// 校验实际生成的 assets/pets.json（3 物种 × 4 阶段 × 4 动作，帧/调色板自洽）。
final class PetLibraryTests: XCTestCase {

    private func loadCatalog() throws -> PetCatalog {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/pets.json")
        return try PetLibrary.load(from: url)
    }

    func testCatalogShape() throws {
        let cat = try loadCatalog()
        XCTAssertEqual(cat.speciesIDs.sorted(), ["aqua", "ember", "sprout"])
        for sp in cat.species {
            XCTAssertFalse(sp.palette.isEmpty)
            XCTAssertEqual(sp.stages.map(\.stage), ["egg", "juvenile", "mature", "final"])
            for st in sp.stages {
                for key in ["idle", "working", "waiting", "complete"] {
                    XCTAssertFalse(st.anims[key]?.frames.isEmpty ?? true, "\(sp.id)/\(st.stage) 缺 \(key)")
                }
                XCTAssertEqual(st.anims["complete"]?.loop, false)  // 完成动画一次性
            }
        }
    }

    func testFramesAreWellFormed() throws {
        let cat = try loadCatalog()
        for sp in cat.species {
            for st in sp.stages {
                for (_, anim) in st.anims {
                    for frame in anim.frames {
                        XCTAssertEqual(Set(frame.map(\.count)).count, 1, "\(sp.id)/\(st.stage) 行宽不一致")
                        for row in frame {
                            for ch in row where ch != "." {
                                XCTAssertNotNil(sp.palette[String(ch)], "\(sp.id) 缺色位 \(ch)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testDecodeInline() throws {
        let json =
            ##"{"schemaVersion":1,"species":[{"id":"x","name":"X","element":"grass","palette":{"A":"#ffffff"},"stages":[{"stage":"egg","anims":{"idle":{"fps":3,"loop":true,"frames":[["A."]]}}}]}]}"##
        let cat = try PetLibrary.decode(Data(json.utf8))
        XCTAssertEqual(cat.species(id: "x")?.stage("egg")?.anims["idle"]?.fps, 3)
    }
}
