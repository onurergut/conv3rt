import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import Conv3rtCore

/// Generates synthetic fixtures with known sample values — no external files,
/// so tests are reproducible and license-clean.
enum Fixtures {

    /// A small RGBA8 image with fully opaque, semi-transparent and fully
    /// transparent pixels that carry distinct RGB values (so alpha-preservation
    /// bugs and "transparent pixels lose their color" bugs surface).
    static func rgbaSample(width: Int = 4, height: Int = 4) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i + 0] = UInt8((x * 40 + 10) % 256)   // R
                bytes[i + 1] = UInt8((y * 40 + 20) % 256)   // G
                bytes[i + 2] = UInt8((x * y + 30) % 256)    // B
                let a: Int
                if x == 0 && y == 0 { a = 255 }          // opaque
                else if x == 1 && y == 0 { a = 128 }     // semi
                else if x == 2 && y == 0 { a = 0 }       // fully transparent, nonzero RGB
                else { a = 255 }
                bytes[i + 3] = UInt8(a)
            }
        }
        return image(from: bytes, width: width, height: height)
    }

    /// An opaque RGB image with more than 256 distinct colors.
    static func manyColors(width: Int = 32, height: Int = 32) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i + 0] = UInt8((x * 8) % 256)
                bytes[i + 1] = UInt8((y * 8) % 256)
                bytes[i + 2] = UInt8(((x + y) * 4) % 256)
                bytes[i + 3] = 255
            }
        }
        return image(from: bytes, width: width, height: height)
    }

    static func image(from rgba: [UInt8], width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: rgba.count)
        rgba.withUnsafeBufferPointer { src in
            buf.update(from: src.baseAddress!, count: rgba.count)
        }
        return ctx.makeImage()!
    }

    /// Writes a CGImage to a temp file with the given UTI. Returns the URL.
    @discardableResult
    static func write(_ image: CGImage, uti: String, ext: String, directory: URL,
                      name: String = "fixture", properties: [CFString: Any]? = nil) throws -> URL {
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).\(ext)")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else {
            throw NSError(domain: "fixtures", code: 1)
        }
        CGImageDestinationAddImage(dest, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "fixtures", code: 2) }
        return url
    }

    /// Writes several images as one multi-frame container (TIFF/ICO/ICNS).
    @discardableResult
    static func writeMulti(_ images: [CGImage], uti: String, ext: String, directory: URL,
                           name: String) throws -> URL {
        let url = directory.appendingPathComponent("\(name)-\(UUID().uuidString).\(ext)")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, images.count, nil) else {
            throw NSError(domain: "fixtures", code: 10)
        }
        for img in images { CGImageDestinationAddImage(dest, img, nil) }
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "fixtures", code: 11) }
        return url
    }

    /// A 2-page TIFF.
    static func multipageTIFF(directory: URL, pages: Int = 2) throws -> URL {
        let images = (0..<pages).map { i -> CGImage in
            image(from: gradient(index: i), width: 8, height: 8)
        }
        return try writeMulti(images, uti: "public.tiff", ext: "tiff", directory: directory, name: "pages")
    }

    /// An animated GIF with `frames` frames and a fixed delay per frame.
    static func animatedGIF(directory: URL, frames: Int = 3) throws -> URL {
        let url = directory.appendingPathComponent("anim-\(UUID().uuidString).gif")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, frames, nil) else {
            throw NSError(domain: "fixtures", code: 12)
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<frames {
            let img = image(from: gradient(index: i), width: 8, height: 8)
            let props: [CFString: Any] = [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime: 0.1]] as [CFString: Any]
            CGImageDestinationAddImage(dest, img, props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "fixtures", code: 13) }
        return url
    }

    /// A 16-bit grayscale PNG, to exercise bit-depth handling.
    static func gray16PNG(directory: URL) throws -> URL {
        let width = 8, height = 8
        let space = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 16,
                            bytesPerRow: width * 2, space: space,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let buf = ctx.data!.bindMemory(to: UInt16.self, capacity: width * height)
        for i in 0..<(width * height) { buf[i] = UInt16((i * 1000) % 65536) }
        let img = ctx.makeImage()!
        return try write(img, uti: "public.png", ext: "png", directory: directory, name: "gray16")
    }

    private static func gradient(index: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in 0..<(8 * 8) {
            bytes[i * 4 + 0] = UInt8((i * 4 + index * 20) % 256)
            bytes[i * 4 + 1] = UInt8((i * 2) % 256)
            bytes[i * 4 + 2] = UInt8(index * 30 % 256)
        }
        return bytes
    }

    /// A one-page PDF.
    static func pdfFixture(directory: URL, pages: Int = 1) throws -> URL {
        let url = directory.appendingPathComponent("doc-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 200)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "fixtures", code: 20)
        }
        for i in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(red: CGFloat(i) / CGFloat(max(pages, 1)) + 0.1, green: 0.4, blue: 0.8, alpha: 1)
            ctx.fill(mediaBox)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    /// A small static SVG.
    static func svgFixture(directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("vector-\(UUID().uuidString).svg")
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="96" height="96">
        <rect width="96" height="96" fill="#3366cc"/>
        <circle cx="48" cy="48" r="30" fill="#ffcc00"/>
        </svg>
        """
        try svg.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A PNG carrying EXIF + GPS metadata, for metadata-policy tests.
    static func pngWithMetadata(directory: URL) throws -> URL {
        let props: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "conv3rt test",
            ] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.0082,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 28.9784,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
        ]
        return try write(rgbaSample(), uti: "public.png", ext: "png", directory: directory,
                         name: "withmeta", properties: props)
    }

    /// Decodes the first frame as tightly packed RGBA8 bytes for exact comparison.
    static func rgbaBytes(of url: URL) throws -> (bytes: [UInt8], width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "fixtures", code: 3)
        }
        return try rgbaBytes(of: image)
    }

    static func rgbaBytes(of image: CGImage) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (bytes, width, height)
    }
}

/// A temp directory cleaned up per test.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("conv3rt-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
