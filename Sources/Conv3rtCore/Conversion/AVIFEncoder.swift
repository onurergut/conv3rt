import Foundation
import CoreGraphics
#if CONV3RT_AVIF
import CAVIF
#endif

/// Encodes images to AVIF (lossy) using a bundled libavif + libaom, when it has
/// been built.
///
/// libavif is only linked when `scripts/build-avif.sh` has produced it (see
/// Package.swift). Without it, `isAvailable` is false and AVIF is not offered
/// as an output target. AVIF has no lossless path here: the RGB→YUV round trip
/// is lossy, so `lossless` is ignored (the planner already blocks it).
public enum AVIFEncoder {

#if CONV3RT_AVIF
    public static var isAvailable: Bool { true }

    public static func encode(image: CGImage, lossless: Bool, quality: Double,
                              icc: [UInt8]? = nil) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let iccBytes: [UInt8] = icc
            ?? buffer.colorSpace.copyICCData().map { Array($0 as Data) } ?? []

        var out: UnsafeMutablePointer<UInt8>?
        var outSize = 0
        func run(_ iccPtr: UnsafePointer<UInt8>?, _ iccLen: Int) -> Int32 {
            buffer.bytes.withUnsafeBufferPointer { src in
                conv3rt_avif_encode_rgba(src.baseAddress, Int32(buffer.width), Int32(buffer.height),
                                         Int32(buffer.width * 4),
                                         Float(max(0, min(quality, 1))),
                                         iccPtr, iccLen, &out, &outSize)
            }
        }
        let rc: Int32 = iccBytes.isEmpty
            ? run(nil, 0)
            : iccBytes.withUnsafeBufferPointer { run($0.baseAddress, $0.count) }
        guard rc == 0, let out else {
            throw ConversionError.encodeFailed("libavif failed (code \(rc)).")
        }
        defer { free(out) }
        return Data(bytes: out, count: outSize)
    }
#else
    public static var isAvailable: Bool { false }

    public static func encode(image: CGImage, lossless: Bool, quality: Double,
                              icc: [UInt8]? = nil) throws -> Data {
        throw ConversionError.encodeFailed("AVIF support is not built into this binary.")
    }
#endif
}
