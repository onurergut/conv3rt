import Foundation
import CoreGraphics
#if CONV3RT_JXL
import CJXL
#endif

/// Encodes images to JPEG XL using a bundled libjxl, when it has been built.
///
/// libjxl is only linked when `scripts/build-jxl.sh` has produced it (see
/// Package.swift). Without it, `isAvailable` is false and JPEG XL is not offered
/// as an output target.
public enum JXLEncoder {

#if CONV3RT_JXL
    public static var isAvailable: Bool { true }

    public static func encode(image: CGImage, lossless: Bool, quality: Double,
                              exif: [UInt8]? = nil, xmp: [UInt8]? = nil) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let icc: [UInt8] = buffer.preservedSamples
            ? (image.colorSpace?.copyICCData().map { Array($0 as Data) } ?? [])
            : []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0
        func run(_ iccPtr: UnsafePointer<UInt8>?, _ iccLen: Int,
                 _ exifPtr: UnsafePointer<UInt8>?, _ exifLen: Int,
                 _ xmpPtr: UnsafePointer<UInt8>?, _ xmpLen: Int) -> Int32 {
            buffer.bytes.withUnsafeBufferPointer { src in
                conv3rt_jxl_encode_rgba(src.baseAddress, Int32(buffer.width), Int32(buffer.height),
                                        lossless ? 1 : 0, Float(max(0, min(quality, 1))),
                                        iccPtr, iccLen, exifPtr, exifLen, xmpPtr, xmpLen,
                                        &out, &outSize)
            }
        }
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
            throw ConversionError.encodeFailed("libjxl failed (code \(rc)).")
        }
        defer { free(out) }
        return Data(bytes: out, count: outSize)
    }
#else
    public static var isAvailable: Bool { false }

    public static func encode(image: CGImage, lossless: Bool, quality: Double,
                              exif: [UInt8]? = nil, xmp: [UInt8]? = nil) throws -> Data {
        throw ConversionError.encodeFailed("JPEG XL support is not built into this binary.")
    }
#endif
}
