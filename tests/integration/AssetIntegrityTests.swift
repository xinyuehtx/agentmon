import CoreGraphics
import ImageIO
import XCTest

@testable import agentmonCore

/// 桌宠图集「门禁」：结构 + 几何 + 帧非空 + 抠图掉帧 + 补帧重影检测。
/// 目标：把「丢帧 / 错位切片 / 抠图过狠丢主体 / 补帧重影(不同动作帧糊在一起)」这类问题挡在 CI。
/// 默认英雄包 verdant 为 v3 多形态（egg/baby/youth/mature × 8 动作），故按「每形态每动作」逐条校验。
final class AssetIntegrityTests: XCTestCase {

    /// 所有随包图集包根目录（packs/ 下每个子目录一个 v2/v3 包）。
    private var packsDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("assets/pets_raster/packs")
    }
    /// 默认英雄包。
    private var verdantDir: URL { packsDir.appendingPathComponent("verdant") }

    /// 活体必需动作（渲染层会用到）。
    private let requiredActions = ["idle", "working", "waiting", "complete", "evolve", "hungry"]
    /// 补帧重影阈值：单动作「半透明像素占比」中位数不得超过此值（重影会产生大片半透明叠影）。
    private let ghostMedianLimit = 0.33

    private func manifest(_ dir: URL) throws -> RasterManifest {
        try RasterLibrary.load(from: dir.appendingPathComponent("manifest.json"))
    }

    /// 收集一个包内所有 (标签, 动作)：v3 各形态 + v2 顶层。
    private func jobs(_ m: RasterManifest) -> [(String, RasterAction)] {
        var out: [(String, RasterAction)] = []
        for s in m.stages ?? [] {
            for (k, a) in s.actions { out.append(("\(s.stage)/\(k)", a)) }
        }
        for (k, a) in m.actions { out.append((k, a)) }
        return out
    }

    private func loadCG(_ dir: URL, _ rel: String) -> CGImage? {
        let url = dir.appendingPathComponent(rel)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private func sliceFrames(_ strip: CGImage, count: Int) -> [CGImage] {
        let fw = strip.width / max(1, count)
        return (0..<count).compactMap {
            strip.cropping(to: CGRect(x: $0 * fw, y: 0, width: fw, height: strip.height))
        }
    }

    /// 返回 (内容像素数 a>16, 半透明像素数 40<a<215)。
    private func alphaStats(_ cg: CGImage) -> (content: Int, partial: Int) {
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return (0, 0) }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard
            let ctx = CGContext(
                data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (0, 0) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var content = 0
        var partial = 0
        var i = 3
        while i < data.count {
            let a = Int(data[i])
            if a > 16 {
                content += 1
                if a > 40 && a < 215 { partial += 1 }
            }
            i += 4
        }
        return (content, partial)
    }

    private func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[s.count / 2]
    }

    // MARK: - 门禁

    /// verdant 结构：v3 多形态、character 正确、每形态齐备必需动作、动作文件都存在。
    func testManifestStructureAndFiles() throws {
        let m = try manifest(verdantDir)
        XCTAssertEqual(m.schemaVersion, 3)
        XCTAssertEqual(m.character, "verdant")
        let stages = m.stages ?? []
        XCTAssertEqual(stages.count, 4, "verdant 应为 4 形态")
        for s in stages {
            for key in requiredActions {
                XCTAssertNotNil(s.actions[key], "形态 \(s.stage) 缺必需动作 \(key)")
            }
        }
        for (label, a) in jobs(m) {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: verdantDir.appendingPathComponent(a.file).path),
                "缺动作文件 \(label) → \(a.file)")
        }
    }

    /// 每条 strip 宽度 == frames×fw、高度 == fh == frameHeight（防丢帧/错位切片）。
    func testStripGeometry() throws {
        let m = try manifest(verdantDir)
        for (label, a) in jobs(m) {
            guard let strip = loadCG(verdantDir, a.file) else { return XCTFail("无法加载 \(a.file)") }
            XCTAssertEqual(strip.width, a.frames * a.fw, "\(label) 宽度与 frames×fw 不符")
            XCTAssertEqual(strip.height, a.fh, "\(label) 高度与 fh 不符")
            XCTAssertEqual(a.fh, m.frameHeight, "\(label) fh 与 frameHeight 不符")
        }
    }

    /// 每帧都要有可见内容（防空白/丢帧）。
    func testNoEmptyFrames() throws {
        let m = try manifest(verdantDir)
        for (label, a) in jobs(m) {
            guard let strip = loadCG(verdantDir, a.file) else { return XCTFail("无法加载 \(a.file)") }
            for (i, f) in sliceFrames(strip, count: a.frames).enumerated() {
                let s = alphaStats(f)
                let total = f.width * f.height
                XCTAssertGreaterThan(
                    Double(s.content) / Double(max(1, total)), 0.005, "\(label) 第 \(i) 帧几乎空白")
            }
        }
    }

    /// 抠图掉帧门禁：视频转包时若抠图过狠（如全屏特效帧把主体也抠掉），
    /// 该帧不透明面积会骤降 → 播放时闪烁/掉帧。扫描 packs/ 下每个动作条，
    /// 任一帧内容面积 < 该动作中位数的 25% 即判失败。覆盖 v2 单形态与 v3 多形态包。
    func testPackFramesNoDropout() throws {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: packsDir.path) else {
            return XCTFail("缺 packs/ 目录")
        }
        for pack in names.sorted() {
            let dir = packsDir.appendingPathComponent(pack)
            let mf = dir.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: mf.path),
                let m = try? RasterLibrary.load(from: mf)
            else { continue }
            for (label, a) in jobs(m) {
                guard let strip = loadCG(dir, a.file) else { return XCTFail("无法加载 \(a.file)") }
                let areas = sliceFrames(strip, count: a.frames).map { Double(alphaStats($0).content) }
                guard !areas.isEmpty else { continue }
                let med = median(areas)
                guard med > 0 else { return XCTFail("\(pack)/\(label) 全空") }
                let minA = areas.min() ?? 0
                XCTAssertGreaterThanOrEqual(
                    minA, 0.25 * med,
                    "\(pack)/\(label) 疑似抠图掉帧：最小帧内容 \(Int(minA)) < 中位数 \(Int(med)) 的 25%")
            }
        }
    }

    /// 补帧重影门禁：大位移动作若强行光流插帧会糊成半透明叠影（不同姿态叠在一起）。
    func testNoInterpolationGhosting() throws {
        let m = try manifest(verdantDir)
        for (label, a) in jobs(m) {
            guard let strip = loadCG(verdantDir, a.file) else { return XCTFail("无法加载 \(a.file)") }
            let fracs = sliceFrames(strip, count: a.frames).map { f -> Double in
                let s = alphaStats(f)
                return s.content > 0 ? Double(s.partial) / Double(s.content) : 0
            }
            let med = median(fracs)
            XCTAssertLessThanOrEqual(
                med, ghostMedianLimit,
                "动作 \(label) 疑似补帧重影：半透明占比中位数 \(String(format: "%.3f", med)) > \(ghostMedianLimit)")
        }
    }
}
