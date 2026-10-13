import Foundation
import CoreGraphics
import CWebP

/// Encodes images to WebP using the bundled libwebp.
///
/// Lossless encodes use libwebp's `exact` mode so the RGB values under fully
/// transparent pixels are preserved — otherwise those channels are free to
/// drift, which would violate the lossless contract.
public enum WebPEncoder {

    /// Whether a WebP encoder is compiled into this build.
    public static var isAvailable: Bool { true }

    /// Encodes one image as a single-frame WebP.
    /// - Parameter lossless: true for a lossless (exact) encode.
    /// - Parameter quality: 0…1, used only for lossy encodes.
    /// - Parameter exif: raw EXIF payload (TIFF structure, no `Exif\0\0` header)
    ///   written into the `EXIF` chunk, or nil.
    /// - Parameter xmp: XMP packet written into the `XMP ` chunk, or nil.
    public static func encode(image: CGImage, lossless: Bool, quality: Double,
                              exif: [UInt8]? = nil, xmp: [UInt8]? = nil) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let icc: [UInt8] = image.colorSpace?.copyICCData().map { Array($0 as Data) } ?? []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0

        func run(_ iccPtr: UnsafePointer<UInt8>?, _ iccLen: Int,
                 _ exifPtr: UnsafePointer<UInt8>?, _ exifLen: Int,
                 _ xmpPtr: UnsafePointer<UInt8>?, _ xmpLen: Int) -> Int32 {
            buffer.bytes.withUnsafeBufferPointer { src in
                conv3rt_webp_encode_rgba(src.baseAddress, Int32(buffer.width), Int32(buffer.height),
                                         Int32(buffer.width * 4), lossless ? 1 : 0,
                                         Float(max(0, min(quality, 1)) * 100),
                                         iccPtr, iccLen, exifPtr, exifLen, xmpPtr, xmpLen,
                                         &out, &outSize)
            }
        }

        // Nest the optional buffers so each stays valid for the call.
        func withOpt<T>(_ a: [UInt8]?, _ body: (UnsafePointer<UInt8>?, Int) -> T) -> T {
            guard let a else { return body(nil, 0) }
            return a.withUnsafeBufferPointer { body($0.baseAddress, $0.count) }
        }

        let rc: Int32 = withOpt(icc.isEmpty ? nil : icc) { iccPtr, iccLen in
            withOpt(exif) { exifPtr, exifLen in
                withOpt(xmp) { xmpPtr, xmpLen in
                    run(iccPtr, iccLen, exifPtr, exifLen, xmpPtr, xmpLen)
                }
            }
        }

        guard rc == 0, let out else {
            throw ConversionError.encodeFailed("libwebp failed (code \(rc)).")
        }
        defer { free(out) }
        return Data(bytes: out, count: outSize)
    }

    /// Encodes several frames as one animated WebP via libwebp's mux animation
    /// encoder. All frames must share one pixel size. `duration` is in seconds.
    /// Lossless encodes use libwebp's `exact` mode so the RGB values under fully
    /// transparent pixels are preserved, matching the single-frame path.
    ///
    /// - Parameter lossless: true for a lossless (exact) encode.
    /// - Parameter quality: 0…1, used only for lossy encodes.
    /// - Parameter loopCount: number of animation loops; 0 repeats forever.
    public static func encodeAnimated(frames: [(image: CGImage, duration: Double)],
                                      lossless: Bool, quality: Double, loopCount: Int,
                                      exif: [UInt8]? = nil, xmp: [UInt8]? = nil) throws -> Data {
        guard let first = frames.first else {
            throw ConversionError.encodeFailed("Animated WebP needs at least one frame.")
        }
        let firstBuffer = try RGBABuffer.tightlyPacked(from: first.image)
        let width = firstBuffer.width, height = firstBuffer.height

        // Frames are laid back to back in one buffer so a single pointer reaches
        // all of them; the encoder indexes by height * stride.
        var blob = firstBuffer.bytes
        blob.reserveCapacity(width * height * 4 * frames.count)
        var durationsMs: [Int32] = [Self.millis(first.duration)]
        durationsMs.reserveCapacity(frames.count)
        for f in frames.dropFirst() {
            let buffer = try RGBABuffer.tightlyPacked(from: f.image)
            guard buffer.width == width, buffer.height == height else {
                throw ConversionError.encodeFailed("Animated WebP frames must share one size.")
            }
            blob.append(contentsOf: buffer.bytes)
            durationsMs.append(Self.millis(f.duration))
        }

        let icc: [UInt8] = first.image.colorSpace?.copyICCData().map { Array($0 as Data) } ?? []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0
        func withOpt<T>(_ a: [UInt8]?, _ body: (UnsafePointer<UInt8>?, Int) -> T) -> T {
            guard let a else { return body(nil, 0) }
            return a.withUnsafeBufferPointer { body($0.baseAddress, $0.count) }
        }

        let rc: Int32 = blob.withUnsafeBufferPointer { src in
            durationsMs.withUnsafeBufferPointer { durs in
                withOpt(icc.isEmpty ? nil : icc) { iccPtr, iccLen in
                    withOpt(exif) { exifPtr, exifLen in
                        withOpt(xmp) { xmpPtr, xmpLen in
                            conv3rt_webp_encode_anim_rgba(
                                src.baseAddress, Int32(width), Int32(height), Int32(width * 4),
                                durs.baseAddress, Int32(frames.count),
                                lossless ? 1 : 0, Float(max(0, min(quality, 1)) * 100),
                                Int32(loopCount),
                                iccPtr, iccLen, exifPtr, exifLen, xmpPtr, xmpLen,
                                &out, &outSize)
                        }
                    }
                }
            }
        }

        guard rc == 0, let out else {
            throw ConversionError.encodeFailed("libwebp failed (code \(rc)).")
        }
        defer { free(out) }
        return Data(bytes: out, count: outSize)
    }

    /// Seconds → whole milliseconds, clamped to a non-negative `int`.
    private static func millis(_ seconds: Double) -> Int32 {
        let ms = (seconds * 1000).rounded()
        return Int32(max(0, min(ms, Double(Int32.max))))
    }
}

/// Extracts 8-bit non-premultiplied RGBA bytes from a `CGImage`, preserving the
/// RGB values of fully transparent pixels when the source stores them.
enum RGBABuffer {

    struct Buffer {
        let bytes: [UInt8]
        let width: Int
        let height: Int
    }

    static func tightlyPacked(from image: CGImage) throws -> Buffer {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { throw ConversionError.encodeFailed("Empty image.") }

        let orderBits = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let isHostOrder = orderBits == 0
            || orderBits == CGBitmapInfo.byteOrder32Little.rawValue
            || orderBits == CGBitmapInfo.byteOrder16Little.rawValue

        // Fast path: 8-bit RGB(A) image whose samples are already what we need.
        if image.bitsPerComponent == 8,
           let space = image.colorSpace, space.model == .rgb,
           let cfData = image.dataProvider?.data,
           isHostOrder {
            let ptr = CFDataGetBytePtr(cfData)!
            let srcStride = image.bytesPerRow
            var out = [UInt8](repeating: 255, count: width * height * 4)

            switch image.alphaInfo {
            case .none:
                for y in 0..<height {
                    for x in 0..<width {
                        let s = y * srcStride + x * 3
                        let d = (y * width + x) * 4
                        out[d + 0] = ptr[s + 0]
                        out[d + 1] = ptr[s + 1]
                        out[d + 2] = ptr[s + 2]
                        out[d + 3] = 255
                    }
                }
                return Buffer(bytes: out, width: width, height: height)
            case .last:   // RGBA, non-premultiplied — the exact case we must preserve.
                for y in 0..<height {
                    let s = y * srcStride
                    let d = y * width * 4
                    for i in 0..<(width * 4) { out[d + i] = ptr[s + i] }
                }
                return Buffer(bytes: out, width: width, height: height)
            default:
                break // premultiplied / gray / other → general path below
            }
        }

        // General path: draw into a premultiplied RGBA context. Note: this
        // cannot recover RGB under alpha=0 (Core Graphics bitmap contexts are
        // always premultiplied), which is why the fast path exists.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Buffer(bytes: out, width: width, height: height)
    }
}
