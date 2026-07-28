import CoreGraphics
import ImageIO
import XCTest

@testable import agentmonCore

/// 桌宠图集「门禁」：结构 + 几何 + 立绘尺寸一致 + 帧非空 + 补帧重影检测。
/// 目的：把「立绘尺寸不一致 / 丢帧 / 补帧重影(不同动作帧糊在一起)」这类问题挡在 CI。
final class AssetIntegrityTests: XCTestCase {

    private var baseDir: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("assets/pets_raster")
    }

    /// 活体必需动作（渲染层会用到）。
    private let requiredActions = ["idle", "working", "waiting", "complete", "evolve", "hungry"]
    /// 补帧重影阈值：单动作「半透明像素占比」中位数不得超过此值（重影会产生大片半透明叠影）。
    private let ghostMedianLimit = 0.33

    private func manifest() throws -> RasterManifest {
        try RasterLibrary.load(from: baseDir.appendingPathComponent("manifest.json"))
    }

    private func loadCG(_ rel: String) -> CGImage? {
        let url = baseDir.appendingPathComponent(rel)
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

    func testManifestStructureAndFiles() throws {
        let m = try manifest()
        XCTAssertEqual(m.schemaVersion, 2)
        XCTAssertEqual(m.character, "aurora")
        for key in requiredActions {
            XCTAssertNotNil(m.action(key), "缺必需动作 \(key)")
        }
        for (_, a) in m.actions {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(a.file).path),
                "缺动作文件 \(a.file)")
        }
        XCTAssertEqual(m.elements.count, 12)
        for e in m.elements {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: baseDir.appendingPathComponent(e.portrait).path),
                "缺立绘 \(e.portrait)")
        }
    }

    /// 每条 strip 宽度 == frames×fw、高度 == fh == frameHeight（防丢帧/错位切片）。
    func testStripGeometry() throws {
        let m = try manifest()
        for (key, a) in m.actions {
            guard let strip = loadCG(a.file) else { return XCTFail("无法加载 \(a.file)") }
            XCTAssertEqual(strip.width, a.frames * a.fw, "\(key) 宽度与 frames×fw 不符")
            XCTAssertEqual(strip.height, a.fh, "\(key) 高度与 fh 不符")
            XCTAssertEqual(a.fh, m.frameHeight, "\(key) fh 与 frameHeight 不符")
        }
    }

    /// 12 张元素立绘尺寸必须完全一致（否则图鉴里大小不一）。
    func testPortraitsUniformSize() throws {
        let m = try manifest()
        var dims: Set<String> = []
        for e in m.elements {
            guard let cg = loadCG(e.portrait) else { return XCTFail("无法加载 \(e.portrait)") }
            dims.insert("\(cg.width)x\(cg.height)")
        }
        XCTAssertEqual(dims.count, 1, "元素立绘尺寸不一致：\(dims.sorted())")
    }

    /// 每帧都要有可见内容（防空白/丢帧）。
    func testNoEmptyFrames() throws {
        let m = try manifest()
        for (key, a) in m.actions {
            guard let strip = loadCG(a.file) else { return XCTFail("无法加载 \(a.file)") }
            for (i, f) in sliceFrames(strip, count: a.frames).enumerated() {
                let s = alphaStats(f)
                let total = f.width * f.height
                XCTAssertGreaterThan(
                    Double(s.content) / Double(max(1, total)), 0.005, "\(key) 第 \(i) 帧几乎空白")
            }
        }
    }

    /// 补帧重影门禁：大位移动作若强行光流插帧会糊成半透明叠影（不同姿态叠在一起）。
    func testNoInterpolationGhosting() throws {
        let m = try manifest()
        for (key, a) in m.actions {
            guard let strip = loadCG(a.file) else { return XCTFail("无法加载 \(a.file)") }
            let fracs = sliceFrames(strip, count: a.frames).map { f -> Double in
                let s = alphaStats(f)
                return s.content > 0 ? Double(s.partial) / Double(s.content) : 0
            }
            let med = median(fracs)
            XCTAssertLessThanOrEqual(
                med, ghostMedianLimit,
                "动作 \(key) 疑似补帧重影：半透明占比中位数 \(String(format: "%.3f", med)) > \(ghostMedianLimit)")
        }
    }
}
