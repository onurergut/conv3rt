// Renders the conv3rt app icon (all iconset sizes) into an output directory.
// Usage: swift scripts/make-icon.swift <outdir>
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> CGImage? {
    let px = Int(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

    // Rounded-rect background with a vertical blue gradient (macOS-like).
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()

    let top = CGColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1)
    let bottom = CGColor(red: 0.18, green: 0.32, blue: 0.86, alpha: 1)
    let grad = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Two "format" chips and an arrow between them.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    let chipW = size * 0.22, chipH = size * 0.28
    let chipY = (size - chipH) / 2
    let leftRect = CGRect(x: size * 0.16, y: chipY, width: chipW, height: chipH)
    let rightRect = CGRect(x: size * 0.62, y: chipY, width: chipW, height: chipH)
    ctx.addPath(CGPath(roundedRect: leftRect, cornerWidth: size * 0.05, cornerHeight: size * 0.05, transform: nil))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: rightRect, cornerWidth: size * 0.05, cornerHeight: size * 0.05, transform: nil))
    ctx.fillPath()

    // Arrow.
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(size * 0.055)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let midY = size / 2
    ctx.move(to: CGPoint(x: size * 0.40, y: midY))
    ctx.addLine(to: CGPoint(x: size * 0.60, y: midY))
    ctx.move(to: CGPoint(x: size * 0.545, y: midY + size * 0.05))
    ctx.addLine(to: CGPoint(x: size * 0.60, y: midY))
    ctx.addLine(to: CGPoint(x: size * 0.545, y: midY - size * 0.05))
    ctx.strokePath()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 2) }
}

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in specs {
    guard let img = drawIcon(size: CGFloat(size)) else { continue }
    try writePNG(img, to: "\(outDir)/\(name)")
}
print("wrote \(specs.count) icon PNGs to \(outDir)")
