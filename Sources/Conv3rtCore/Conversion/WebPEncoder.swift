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
                              exif: [UInt8]? = nil, xmp: [UInt8]? = nil,
                              isCancelled: @escaping () -> Bool = { false },
                              progress: (@Sendable (Double) -> Void)? = nil) throws -> Data {
        if isCancelled() { throw ConversionError.canceled }
        guard image.width <= 16383, image.height <= 16383 else {
            throw ConversionError.encodeFailed("WebP dimensions must not exceed 16383 pixels.")
        }
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let icc: [UInt8] = buffer.colorSpace.copyICCData().map { Array($0 as Data) } ?? []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0
        let control = EncodingControl(isCancelled: isCancelled, progress: progress)
        let context = Unmanaged.passUnretained(control).toOpaque()
        defer { withExtendedLifetime(control) {} }

        func run(_ iccPtr: UnsafePointer<UInt8>?, _ iccLen: Int,
                 _ exifPtr: UnsafePointer<UInt8>?, _ exifLen: Int,
                 _ xmpPtr: UnsafePointer<UInt8>?, _ xmpLen: Int) -> Int32 {
            buffer.bytes.withUnsafeBufferPointer { src in
                conv3rt_webp_encode_rgba(src.baseAddress, Int32(buffer.width), Int32(buffer.height),
                                         Int32(buffer.width * 4), lossless ? 1 : 0,
                                         Float(max(0, min(quality, 1)) * 100),
                                         iccPtr, iccLen, exifPtr, exifLen, xmpPtr, xmpLen,
                                         reportProgress, context,
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

        if isCancelled() {
            if let out { free(out) }
            throw ConversionError.canceled
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
                                      exif: [UInt8]? = nil, xmp: [UInt8]? = nil,
                                      isCancelled: @escaping () -> Bool = { false },
                                      progress: (@Sendable (Double) -> Void)? = nil) throws -> Data {
        if isCancelled() { throw ConversionError.canceled }
        guard let first = frames.first else {
            throw ConversionError.encodeFailed("Animated WebP needs at least one frame.")
        }
        let firstBuffer = try RGBABuffer.tightlyPacked(from: first.image)
        let width = firstBuffer.width, height = firstBuffer.height
        guard width <= 16383, height <= 16383, frames.count <= Int(Int32.max),
              RasterSizeGuard.fits(width: width, height: height, bytesPerPixel: 8,
                                  additionalBytes: Double(width) * Double(height) * 4 * Double(frames.count)),
              loopCount >= 0, loopCount <= 65535,
              frames.allSatisfy({ $0.duration.isFinite && ($0.duration * 1000).rounded() >= 1
                    && ($0.duration * 1000).rounded() <= 16_777_215
                    && (!lossless || abs($0.duration * 1000 - ($0.duration * 1000).rounded()) < 1e-8) }),
              frames.reduce(0.0, { $0 + ($1.duration * 1000).rounded() }) <= Double(Int32.max) else {
            throw ConversionError.encodeFailed("The WebP animation dimensions, duration or loop count are unsupported.")
        }

        // Frames are laid back to back in one buffer so a single pointer reaches
        // all of them; the encoder indexes by height * stride.
        var blob = firstBuffer.bytes
        blob.reserveCapacity(width * height * 4 * frames.count)
        var durationsMs: [Int32] = [Self.millis(first.duration)]
        durationsMs.reserveCapacity(frames.count)
        for f in frames.dropFirst() {
            if isCancelled() { throw ConversionError.canceled }
            let buffer = try RGBABuffer.tightlyPacked(from: f.image)
            guard buffer.width == width, buffer.height == height else {
                throw ConversionError.encodeFailed("Animated WebP frames must share one size.")
            }
            blob.append(contentsOf: buffer.bytes)
            durationsMs.append(Self.millis(f.duration))
        }

        let icc: [UInt8] = firstBuffer.colorSpace.copyICCData().map { Array($0 as Data) } ?? []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0
        let control = EncodingControl(isCancelled: isCancelled, progress: progress)
        let context = Unmanaged.passUnretained(control).toOpaque()
        defer { withExtendedLifetime(control) {} }
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
                                reportProgress, context,
                                &out, &outSize)
                        }
                    }
                }
            }
        }

        if isCancelled() {
            if let out { free(out) }
            throw ConversionError.canceled
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

    private final class EncodingControl {
        let isCancelled: () -> Bool
        let progress: (@Sendable (Double) -> Void)?
        private var lastPercent: Int32 = -1
        init(isCancelled: @escaping () -> Bool, progress: (@Sendable (Double) -> Void)?) {
            self.isCancelled = isCancelled
            self.progress = progress
        }

        func report(_ percent: Int32) {
            guard percent > lastPercent else { return }
            lastPercent = percent
            progress?(Double(percent) / 100)
        }
    }

    private static let reportProgress: @convention(c) (Int32, UnsafeMutableRawPointer?) -> Int32 = { percent, context in
        guard let context else { return 1 }
        let control = Unmanaged<EncodingControl>.fromOpaque(context).takeUnretainedValue()
        if control.isCancelled() { return 0 }
        control.report(percent)
        return control.isCancelled() ? 0 : 1
    }
}

/// Extracts 8-bit non-premultiplied RGBA bytes from a `CGImage`, preserving the
/// RGB values of fully transparent pixels when the source stores them.
enum RGBABuffer {

    struct Buffer {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let colorSpace: CGColorSpace
    }

    static func tightlyPacked(from image: CGImage) throws -> Buffer {
        let width = image.width, height = image.height
        guard RasterSizeGuard.fits(width: width, height: height, bytesPerPixel: 8) else {
            throw ConversionError.encodeFailed("The RGB conversion buffer is too large or has invalid dimensions.")
        }

        let orderBits = image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue
        let reversed = orderBits == CGBitmapInfo.byteOrder32Little.rawValue

        // Fast path: 8-bit RGB(A) image whose samples are already what we need.
        if image.bitsPerComponent == 8,
           let space = image.colorSpace, space.model == .rgb,
           let cfData = image.dataProvider?.data {
            let ptr = CFDataGetBytePtr(cfData)!
            let srcStride = image.bytesPerRow
            let channels = image.bitsPerPixel / 8
            guard channels == 3 || channels == 4,
                  srcStride >= width * channels,
                  srcStride <= CFDataGetLength(cfData) / height else {
                throw ConversionError.encodeFailed("Unsupported RGB sample layout.")
            }
            var out = [UInt8](repeating: 255, count: width * height * 4)
            let first: Bool
            let alpha: Bool
            let premultiplied: Bool
            switch image.alphaInfo {
            case .none, .noneSkipLast:
                first = false; alpha = false; premultiplied = false
            case .noneSkipFirst:
                first = true; alpha = false; premultiplied = false
            case .last:
                first = false; alpha = true; premultiplied = false
            case .first:
                first = true; alpha = true; premultiplied = false
            case .premultipliedLast:
                first = false; alpha = true; premultiplied = true
            case .premultipliedFirst:
                first = true; alpha = true; premultiplied = true
            default:
                throw ConversionError.encodeFailed("Unsupported RGB alpha layout.")
            }
            for y in 0..<height {
                for x in 0..<width {
                    let s = y * srcStride + x * channels
                    let d = (y * width + x) * 4
                    func component(_ index: Int) -> UInt8 {
                        ptr[s + (reversed && channels == 4 ? 3 - index : index)]
                    }
                    let a = alpha ? component(first ? 0 : 3) : 255
                    for channel in 0..<3 {
                        let value = component(channel + (first ? 1 : 0))
                        out[d + channel] = premultiplied && a > 0
                            ? UInt8(min(255, (Int(value) * 255 + Int(a) / 2) / Int(a))) : value
                    }
                    out[d + 3] = a
                }
            }
            return Buffer(bytes: out, width: width, height: height, colorSpace: space)
        }

        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ConversionError.encodeFailed("Could not allocate the RGB conversion buffer.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage() else {
            throw ConversionError.encodeFailed("Could not prepare the RGB samples.")
        }
        let buffer = try tightlyPacked(from: rendered)
        return Buffer(bytes: buffer.bytes, width: width, height: height,
                      colorSpace: space)
    }
}
