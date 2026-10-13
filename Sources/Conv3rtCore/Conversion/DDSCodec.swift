import Foundation
import CoreGraphics

/// Lossless codec for uncompressed DirectDraw Surface images (magic "DDS ").
public enum DDSCodec {

    public enum Error: Swift.Error, LocalizedError, Equatable, Sendable {
        case invalidHeader
        case unsupported
        case truncated

        public var errorDescription: String? {
            switch self {
            case .invalidHeader: return "Not a valid DDS image."
            case .unsupported: return "This DDS pixel format is not supported."
            case .truncated: return "The DDS data ended unexpectedly."
            }
        }
    }

    private static let magic: [UInt8] = [0x44, 0x44, 0x53, 0x20] // "DDS "

    private static let caps = UInt32(0x1)
    private static let height = UInt32(0x2)
    private static let width = UInt32(0x4)
    private static let pitch = UInt32(0x8)
    private static let pixelFormat = UInt32(0x1000)

    public static func canDecode(_ data: Data) -> Bool {
        data.count >= 128 && Array(data.prefix(4)) == magic
    }

    public static func decode(_ data: Data) throws -> CGImage {
        let bytes = [UInt8](data)
        guard bytes.count >= 128, Array(bytes[0..<4]) == magic else { throw Error.invalidHeader }
        guard leU32(bytes, 4) == 124, leU32(bytes, 76) == 32 else { throw Error.invalidHeader }

        let h = Int(leU32(bytes, 12))
        let w = Int(leU32(bytes, 16))
        guard w > 0, h > 0, w <= 0x4000_0000, h <= 0x4000_0000,
              w <= 0x1000_0000 / h else { throw Error.invalidHeader }

        // A nonzero fourCC means a compressed (BCn/DXT) surface we do not decode.
        guard leU32(bytes, 84) == 0 else { throw Error.unsupported }

        let bitCount = Int(leU32(bytes, 88))
        guard bitCount == 32 || bitCount == 24 else { throw Error.unsupported }

        let rMask = leU32(bytes, 92), gMask = leU32(bytes, 96)
        let bMask = leU32(bytes, 100), aMask = leU32(bytes, 104)

        // Uncompressed rows are aligned to a 4-byte pitch.
        let bpp = bitCount / 8
        let pitch = (w * bpp + 3) & ~3
        guard bytes.count >= 128 + pitch * h else { throw Error.truncated }

        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let row = 128 + y * pitch
            for x in 0..<w {
                let o = row + x * bpp
                var px: UInt32 = 0
                for i in 0..<bpp { px |= UInt32(bytes[o + i]) << (8 * i) }
                let d = (y * w + x) * 4
                out[d + 0] = channel(px, rMask)
                out[d + 1] = channel(px, gMask)
                out[d + 2] = channel(px, bMask)
                out[d + 3] = aMask == 0 ? 255 : channel(px, aMask)
            }
        }
        return try RGBAImage.make(from: out, width: w, height: h)
    }

    public static func encode(_ image: CGImage) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let w = buffer.width, h = buffer.height
        let src = buffer.bytes

        var out = [UInt8](repeating: 0, count: 128)
        out[0] = 0x44; out[1] = 0x44; out[2] = 0x53; out[3] = 0x20
        putLE(&out, 4, 124)
        putLE(&out, 8, caps | height | width | pitch | pixelFormat)
        putLE(&out, 12, UInt32(h))
        putLE(&out, 16, UInt32(w))
        putLE(&out, 20, UInt32(w * 4))
        putLE(&out, 76, 32)
        putLE(&out, 80, 0x41)          // DDPF_RGB | DDPF_ALPHAPIXELS
        putLE(&out, 88, 32)
        putLE(&out, 92, 0x00FF_0000)   // R
        putLE(&out, 96, 0x0000_FF00)   // G
        putLE(&out, 100, 0x0000_00FF)  // B
        putLE(&out, 104, 0xFF00_0000)  // A
        putLE(&out, 108, 0x1000)       // DDSCAPS_TEXTURE

        out.reserveCapacity(128 + w * h * 4)
        for i in 0..<(w * h) {
            out.append(src[i * 4 + 2])
            out.append(src[i * 4 + 1])
            out.append(src[i * 4 + 0])
            out.append(src[i * 4 + 3])
        }
        return Data(out)
    }

    private static func channel(_ px: UInt32, _ mask: UInt32) -> UInt8 {
        guard mask != 0 else { return 0 }
        let shift = mask.trailingZeroBitCount
        let v = (px & mask) >> shift
        return UInt8(v &* 255 / (mask >> shift))
    }

    private static func leU32(_ bytes: [UInt8], _ o: Int) -> UInt32 {
        UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8)
            | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
    }

    private static func putLE(_ out: inout [UInt8], _ o: Int, _ v: UInt32) {
        out[o] = UInt8(v & 0xFF)
        out[o + 1] = UInt8((v >> 8) & 0xFF)
        out[o + 2] = UInt8((v >> 16) & 0xFF)
        out[o + 3] = UInt8((v >> 24) & 0xFF)
    }
}
