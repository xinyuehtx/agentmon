#!/usr/bin/env swift
//
// 生成 agentmon 应用图标（离屏 CoreGraphics 绘制，无需 GUI）。
// 用法：从仓库根目录运行  `swift scripts/make-icon.swift`
// 产出：Sources/App/Resources/AppIcon.icns
//
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func draw(_ side: Int) -> CGImage? {
    let s = CGFloat(side)
    let space = CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    // 圆角方形背景 + 暖橙渐变
    let margin = s * 0.085
    let rect = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = rect.width * 0.2237
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let colors =
        [
            CGColor(red: 1.0, green: 0.74, blue: 0.33, alpha: 1),
            CGColor(red: 1.0, green: 0.52, blue: 0.09, alpha: 1),
        ] as CFArray
    if let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    }
    ctx.restoreGState()

    // 白色小猫脸
    let cx = s / 2, cy = s * 0.46, r = rect.width * 0.30
    func tri(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) {
        ctx.beginPath()
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.addLine(to: p3)
        ctx.closePath()
        ctx.fillPath()
    }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    let earH = r * 0.95
    tri(
        CGPoint(x: cx - r * 0.78, y: cy + r * 0.30), CGPoint(x: cx - r * 0.12, y: cy + r * 0.30),
        CGPoint(x: cx - r * 0.5, y: cy + r * 0.30 + earH))
    tri(
        CGPoint(x: cx + r * 0.78, y: cy + r * 0.30), CGPoint(x: cx + r * 0.12, y: cy + r * 0.30),
        CGPoint(x: cx + r * 0.5, y: cy + r * 0.30 + earH))
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))

    // 眼睛
    ctx.setFillColor(CGColor(red: 0.20, green: 0.16, blue: 0.12, alpha: 1))
    let eyeR = r * 0.13
    ctx.fillEllipse(in: CGRect(x: cx - r * 0.38 - eyeR, y: cy + r * 0.06 - eyeR, width: 2 * eyeR, height: 2 * eyeR))
    ctx.fillEllipse(in: CGRect(x: cx + r * 0.38 - eyeR, y: cy + r * 0.06 - eyeR, width: 2 * eyeR, height: 2 * eyeR))

    // 鼻子
    ctx.setFillColor(CGColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1))
    tri(
        CGPoint(x: cx, y: cy - r * 0.20), CGPoint(x: cx - r * 0.12, y: cy - r * 0.02),
        CGPoint(x: cx + r * 0.12, y: cy - r * 0.02))

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard
        let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    guard let image = draw(px) else { fatalError("draw failed at \(px)") }
    writePNG(image, to: iconset.appendingPathComponent("\(name).png"))
}

let out = root.appendingPathComponent("Sources/App/Resources/AppIcon.icns")
try? FileManager.default.createDirectory(
    at: out.deletingLastPathComponent(), withIntermediateDirectories: true)

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("wrote \(out.path) (iconutil exit=\(proc.terminationStatus))")
