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

    public static func encode(image: CGImage, lossless: Bool, quality: Double) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let icc: [UInt8] = image.colorSpace?.copyICCData().map { Array($0 as Data) } ?? []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0
        let run: (UnsafePointer<UInt8>?, Int) -> Int32 = { iccPtr, iccLen in
            buffer.bytes.withUnsafeBufferPointer { src in
                conv3rt_jxl_encode_rgba(src.baseAddress, Int32(buffer.width), Int32(buffer.height),
                                        lossless ? 1 : 0, Float(max(0, min(quality, 1))),
                                        iccPtr, iccLen, &out, &outSize)
            }
        }
        let rc: Int32 = icc.isEmpty
            ? run(nil, 0)
            : icc.withUnsafeBufferPointer { run($0.baseAddress, $0.count) }
        guard rc == 0, let out else {
            throw ConversionError.encodeFailed("libjxl failed (code \(rc)).")
        }
        defer { free(out) }
        return Data(bytes: out, count: outSize)
    }
#else
    public static var isAvailable: Bool { false }

    public static func encode(image: CGImage, lossless: Bool, quality: Double) throws -> Data {
        throw ConversionError.encodeFailed("JPEG XL support is not built into this binary.")
    }
#endif
}
