import Foundation
import CoreGraphics

/// Lossless codec for the Quite OK Image format (spec magic "qoif").
public enum QOICodec {

    public enum Error: Swift.Error, LocalizedError, Equatable, Sendable {
        case invalidHeader
        case truncated

        public var errorDescription: String? {
            switch self {
            case .invalidHeader: return "Not a valid QOI image."
            case .truncated: return "The QOI data ended unexpectedly."
            }
        }
    }

    private static let magic: [UInt8] = [0x71, 0x6F, 0x69, 0x66] // "qoif"

    public static func canDecode(_ data: Data) -> Bool {
        data.count >= 22 && Array(data.prefix(4)) == magic
    }

    public static func decode(_ data: Data) throws -> CGImage {
        let bytes = [UInt8](data)
        guard bytes.count >= 22, Array(bytes[0..<4]) == magic else { throw Error.invalidHeader }
        guard (bytes[12] == 3 || bytes[12] == 4), bytes[13] <= 1,
              Array(bytes.suffix(8)) == [0, 0, 0, 0, 0, 0, 0, 1] else { throw Error.invalidHeader }

        let width = Int(beU32(bytes, 4))
        let height = Int(beU32(bytes, 8))
        guard width > 0, height > 0, width <= 0x4000_0000, height <= 0x4000_0000,
              width <= 0x1000_0000 / height else { throw Error.invalidHeader }

        let count = width * height
        let chunksEnd = bytes.count - 8
        // A run represents at most 62 pixels. Reject short rasters before
        // allocating the expanded image, and include the provider's byte copy.
        guard chunksEnd - 14 >= (count + 61) / 62,
              RasterSizeGuard.fits(width: width, height: height, bytesPerPixel: 8,
                                   additionalBytes: Double(bytes.count) * 2) else { throw Error.invalidHeader }
        var out = [UInt8](repeating: 0, count: count * 4)
        var index = [UInt32](repeating: 0, count: 64)
        var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255
        var p = 14
        var run = 0

        for i in 0..<count {
            if run > 0 {
                run -= 1
            } else {
                guard p < chunksEnd else { throw Error.truncated }
                let tag = bytes[p]; p += 1
                if tag == 0xFE {
                    guard p + 3 <= chunksEnd else { throw Error.truncated }
                    r = bytes[p]; g = bytes[p + 1]; b = bytes[p + 2]; p += 3
                } else if tag == 0xFF {
                    guard p + 4 <= chunksEnd else { throw Error.truncated }
                    r = bytes[p]; g = bytes[p + 1]; b = bytes[p + 2]; a = bytes[p + 3]; p += 4
                } else {
                    switch tag & 0xC0 {
                    case 0x00:
                        let packed = index[Int(tag & 0x3F)]
                        r = UInt8((packed >> 24) & 0xFF); g = UInt8((packed >> 16) & 0xFF)
                        b = UInt8((packed >> 8) & 0xFF); a = UInt8(packed & 0xFF)
                    case 0x40:
                        r = r &+ UInt8(bitPattern: Int8(Int((tag >> 4) & 0x03) - 2))
                        g = g &+ UInt8(bitPattern: Int8(Int((tag >> 2) & 0x03) - 2))
                        b = b &+ UInt8(bitPattern: Int8(Int(tag & 0x03) - 2))
                    case 0x80:
                        guard p < chunksEnd else { throw Error.truncated }
                        let tag2 = bytes[p]; p += 1
                        let dg = Int(tag & 0x3F) - 32
                        let dr = dg - 8 + Int((tag2 >> 4) & 0x0F)
                        let db = dg - 8 + Int(tag2 & 0x0F)
                        r = r &+ UInt8(bitPattern: Int8(truncatingIfNeeded: dr))
                        g = g &+ UInt8(bitPattern: Int8(truncatingIfNeeded: dg))
                        b = b &+ UInt8(bitPattern: Int8(truncatingIfNeeded: db))
                    default:
                        run = Int(tag & 0x3F)
                        guard run < count - i else { throw Error.invalidHeader }
                    }
                }
                index[Int(hash(r, g, b, a))] = (UInt32(r) << 24) | (UInt32(g) << 16) | (UInt32(b) << 8) | UInt32(a)
            }
            out[i * 4] = r; out[i * 4 + 1] = g; out[i * 4 + 2] = b; out[i * 4 + 3] = a
        }
        guard p == chunksEnd, run == 0 else { throw Error.invalidHeader }
        return try RGBAImage.make(from: out, width: width, height: height)
    }

    public static func encode(_ image: CGImage) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let src = buffer.bytes
        let count = buffer.width * buffer.height

        var out = [UInt8]()
        out.reserveCapacity(count * 4 + 22)
        out.append(contentsOf: magic)
        appendBE(&out, UInt32(buffer.width))
        appendBE(&out, UInt32(buffer.height))
        out.append(4)
        out.append(0)

        var index = [UInt32](repeating: 0, count: 64)
        var pr: UInt8 = 0, pg: UInt8 = 0, pb: UInt8 = 0, pa: UInt8 = 255
        var run = 0

        for i in 0..<count {
            let r = src[i * 4], g = src[i * 4 + 1], b = src[i * 4 + 2], a = src[i * 4 + 3]
            let packed = (UInt32(r) << 24) | (UInt32(g) << 16) | (UInt32(b) << 8) | UInt32(a)
            let prev = (UInt32(pr) << 24) | (UInt32(pg) << 16) | (UInt32(pb) << 8) | UInt32(pa)

            if packed == prev {
                run += 1
                if run == 62 || i == count - 1 {
                    out.append(0xC0 | UInt8(run - 1))
                    run = 0
                }
            } else {
                if run > 0 { out.append(0xC0 | UInt8(run - 1)); run = 0 }
                let slot = Int(hash(r, g, b, a))
                if index[slot] == packed {
                    out.append(UInt8(slot))
                } else {
                    index[slot] = packed
                    if a == pa {
                        let dr = Int(Int8(bitPattern: r &- pr))
                        let dg = Int(Int8(bitPattern: g &- pg))
                        let db = Int(Int8(bitPattern: b &- pb))
                        if dr > -3, dr < 2, dg > -3, dg < 2, db > -3, db < 2 {
                            let diff: Int = 0x40 | ((dr + 2) << 4) | ((dg + 2) << 2) | (db + 2)
                            out.append(UInt8(diff))
                        } else {
                            let drdg = dr - dg, dbdg = db - dg
                            if drdg > -9, drdg < 8, dg > -33, dg < 32, dbdg > -9, dbdg < 8 {
                                out.append(UInt8(0x80 | (dg + 32)))
                                let luma: Int = ((drdg + 8) << 4) | (dbdg + 8)
                                out.append(UInt8(luma))
                            } else {
                                out.append(0xFE); out.append(r); out.append(g); out.append(b)
                            }
                        }
                    } else {
                        out.append(0xFF); out.append(r); out.append(g); out.append(b); out.append(a)
                    }
                }
            }
            pr = r; pg = g; pb = b; pa = a
        }

        out.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1])
        return Data(out)
    }

    private static func hash(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> UInt32 {
        (UInt32(r) &* 3 &+ UInt32(g) &* 5 &+ UInt32(b) &* 7 &+ UInt32(a) &* 11) % 64
    }

    private static func beU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
    }

    private static func appendBE(_ out: inout [UInt8], _ value: UInt32) {
        out.append(UInt8((value >> 24) & 0xFF))
        out.append(UInt8((value >> 16) & 0xFF))
        out.append(UInt8((value >> 8) & 0xFF))
        out.append(UInt8(value & 0xFF))
    }
}

/// The planner runs after standalone decoding/rasterization. Bound those
/// earlier workspaces too, using the planner's default 4 GiB budget and the
/// actual intermediate sample buffers rather than the file's packed size.
enum RasterSizeGuard {
    static let maximumBytes = 4.0 * 1024 * 1024 * 1024

    static func fits(width: Int, height: Int, bytesPerPixel: Int, additionalBytes: Double = 0) -> Bool {
        guard width > 0, height > 0, bytesPerPixel > 0,
              additionalBytes.isFinite, additionalBytes >= 0,
              width <= Int.max / height,
              width * height <= Int.max / bytesPerPixel else { return false }
        return Double(width) * Double(height) * Double(bytesPerPixel) + additionalBytes <= maximumBytes
    }

    static func dimensions(size: CGSize, scale: CGFloat, bytesPerPixel: Int = 8) -> (width: Int, height: Int)? {
        guard scale.isFinite, scale > 0, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        let width = max((size.width * scale).rounded(), 1)
        let height = max((size.height * scale).rounded(), 1)
        guard width.isFinite, height.isFinite,
              width < CGFloat(Int.max), height < CGFloat(Int.max) else { return nil }
        let w = Int(width), h = Int(height)
        guard fits(width: w, height: h, bytesPerPixel: bytesPerPixel) else { return nil }
        return (w, h)
    }
}

/// Builds a non-premultiplied sRGB `CGImage` from tightly packed RGBA8 bytes,
/// so channels under fully transparent pixels survive a decode.
enum RGBAImage {
    static func make(from bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw QOICodec.Error.invalidHeader
        }
        return image
    }
}
