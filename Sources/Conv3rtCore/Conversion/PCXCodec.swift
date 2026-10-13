import Foundation
import CoreGraphics

/// Lossless codec for ZSoft PCX. Decodes 24-bit truecolor and 8-bit indexed
/// images; encodes 24-bit truecolor (RLE per spec).
public enum PCXCodec {

    public enum Error: Swift.Error, LocalizedError, Equatable, Sendable {
        case invalidHeader
        case unsupported(String)
        case truncated

        public var errorDescription: String? {
            switch self {
            case .invalidHeader: return "Not a valid PCX image."
            case .unsupported(let detail): return "This PCX variant is not supported. \(detail)"
            case .truncated: return "The PCX data ended unexpectedly."
            }
        }
    }

    public static func canDecode(_ data: Data) -> Bool {
        guard data.count >= 128 else { return false }
        let bytes = [UInt8](data.prefix(4))
        return bytes[0] == 0x0A && bytes[2] == 1
    }

    public static func decode(_ data: Data) throws -> CGImage {
        let bytes = [UInt8](data)
        guard bytes.count >= 128, bytes[0] == 0x0A, bytes[2] == 1 else { throw Error.invalidHeader }

        let bitsPerPixel = Int(bytes[3])
        let width = Int(le16(bytes, 8)) - Int(le16(bytes, 4)) + 1
        let height = Int(le16(bytes, 10)) - Int(le16(bytes, 6)) + 1
        let planes = Int(bytes[65])
        let bytesPerLine = Int(le16(bytes, 66))
        guard width > 0, height > 0, bytesPerLine > 0 else { throw Error.invalidHeader }

        var out = [UInt8](repeating: 255, count: width * height * 4)
        var reader = RLEReader(bytes: bytes, start: 128)

        if bitsPerPixel == 8, planes >= 3 {
            var line = [UInt8](repeating: 0, count: planes * bytesPerLine)
            for y in 0..<height {
                for i in 0..<line.count { line[i] = try reader.next() }
                for x in 0..<width {
                    let d = (y * width + x) * 4
                    out[d] = line[x]
                    out[d + 1] = line[bytesPerLine + x]
                    out[d + 2] = line[2 * bytesPerLine + x]
                }
            }
        } else if bitsPerPixel == 8, planes == 1 {
            guard bytes.count >= 769, bytes[bytes.count - 769] == 0x0C else {
                throw Error.unsupported("8-bit indexed image without a palette trailer.")
            }
            let palette = bytes.count - 768
            var line = [UInt8](repeating: 0, count: bytesPerLine)
            for y in 0..<height {
                for i in 0..<bytesPerLine { line[i] = try reader.next() }
                for x in 0..<width {
                    let base = palette + Int(line[x]) * 3
                    let d = (y * width + x) * 4
                    out[d] = bytes[base]
                    out[d + 1] = bytes[base + 1]
                    out[d + 2] = bytes[base + 2]
                }
            }
        } else {
            throw Error.unsupported("\(bitsPerPixel)bpp with \(planes) plane(s).")
        }

        return try RGBAImage.make(from: out, width: width, height: height)
    }

    public static func encode(_ image: CGImage) throws -> Data {
        let buffer = try RGBABuffer.tightlyPacked(from: image)
        let width = buffer.width, height = buffer.height
        guard width <= 0xFFFF else { throw Error.unsupported("Image wider than 65535 pixels.") }

        let bytesPerLine = width + (width & 1)
        var header = [UInt8](repeating: 0, count: 128)
        header[0] = 0x0A
        header[1] = 5
        header[2] = 1
        header[3] = 8
        setLE(&header, 8, UInt16(width - 1))
        setLE(&header, 10, UInt16(height - 1))
        setLE(&header, 12, 72)
        setLE(&header, 14, 72)
        header[65] = 3
        setLE(&header, 66, UInt16(bytesPerLine))
        setLE(&header, 68, 1)

        let src = buffer.bytes
        var body = [UInt8]()
        body.reserveCapacity(width * height * 3)
        for y in 0..<height {
            for plane in 0..<3 {
                var row = [UInt8](repeating: 0, count: bytesPerLine)
                for x in 0..<width { row[x] = src[(y * width + x) * 4 + plane] }
                appendRLE(&body, row)
            }
        }

        return Data(header + body)
    }

    private static func appendRLE(_ out: inout [UInt8], _ values: [UInt8]) {
        var i = 0
        while i < values.count {
            let value = values[i]
            var run = 1
            while i + run < values.count, values[i + run] == value, run < 63 { run += 1 }
            if run > 1 || value >= 0xC0 {
                out.append(0xC0 | UInt8(run))
            }
            out.append(value)
            i += run
        }
    }

    private static func le16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func setLE(_ bytes: inout [UInt8], _ offset: Int, _ value: UInt16) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
    }
}

/// Reads PCX RLE bytes: a run count byte with the top two bits set is followed
/// by that many copies of one value.
private struct RLEReader {
    let bytes: [UInt8]
    var position: Int
    var run = 0
    var value: UInt8 = 0

    init(bytes: [UInt8], start: Int) {
        self.bytes = bytes
        self.position = start
    }

    mutating func next() throws -> UInt8 {
        if run > 0 { run -= 1; return value }
        guard position < bytes.count else { throw PCXCodec.Error.truncated }
        let byte = bytes[position]; position += 1
        guard byte & 0xC0 == 0xC0 else { return byte }
        guard position < bytes.count else { throw PCXCodec.Error.truncated }
        value = bytes[position]; position += 1
        run = max(Int(byte & 0x3F), 1) - 1
        return value
    }
}
