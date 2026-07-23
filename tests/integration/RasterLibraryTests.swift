import XCTest

@testable import agentmonCore

/// 校验实际生成的 assets/pets_raster/manifest.json 与图集文件齐全、自洽。
final class RasterLibraryTests: XCTestCase {

    private var baseDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets/pets_raster")
    }

    func testManifestAndFilesExist() throws {
        let m = try RasterLibrary.load(from: baseDir.appendingPathComponent("manifest.json"))
        XCTAssertEqual(m.schemaVersion, 1)
        XCTAssertEqual(m.speciesIDs.sorted(), ["bird_fire", "dog_cabbage", "sealion_water"])

        for sp in m.species {
            XCTAssertFalse(sp.stages.isEmpty, "\(sp.id) 无阶段")
            for st in sp.stages {
                XCTAssertFalse(st.actions.isEmpty, "\(sp.id)/\(st.stage) 无动作")
                for (_, a) in st.actions {
                    XCTAssertGreaterThan(a.frames, 0)
                    XCTAssertGreaterThan(a.fw, 0)
                    XCTAssertGreaterThan(a.fh, 0)
                    XCTAssertTrue(
                        FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(a.file).path),
                        "缺文件 \(a.file)")
                }
            }
            // 成熟阶段应四态齐全
            if let mature = sp.stage("mature") {
                for key in ["idle", "working", "waiting", "complete"] {
                    XCTAssertNotNil(mature.actions[key], "\(sp.id) mature 缺 \(key)")
                }
            }
        }
    }
}
