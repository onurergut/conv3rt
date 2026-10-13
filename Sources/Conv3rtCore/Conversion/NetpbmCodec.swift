import Foundation
import CoreGraphics

/// Errors from reading or writing Netpbm-family images.
public enum NetpbmError: Error, LocalizedError, Equatable {
    case notNetpbm
    case malformed(String)
    case unsupported(String)
    case encodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notNetpbm:
            return "The data is not a Netpbm image."
        case .malformed(let detail):
            return "The Netpbm file is malformed. \(detail)"
        case .unsupported(let detail):
            return "This Netpbm variant is not supported. \(detail)"
        case .encodeFailed(let detail):
            return "Netpbm encoding failed. \(detail)"
        }
    }
}

/// Reads and writes the Netpbm family, including Portable Float Map (`PF`/`Pf`),
/// which macOS Image I/O does not read.
public enum NetpbmCodec {

    /// Whether the leading bytes carry a Netpbm magic number (`P1`…`P7`, `PF`, `Pf`).
    public static func canDecode(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(2))
        guard head.count == 2, head[0] == UInt8(ascii: "P") else { return false }
        switch head[1] {
        case UInt8(ascii: "1"), UInt8(ascii: "2"), UInt8(ascii: "3"), UInt8(ascii: "4"),
             UInt8(ascii: "5"), UInt8(ascii: "6"), UInt8(ascii: "7"),
             UInt8(ascii: "F"), UInt8(ascii: "f"):
            return true
        default:
            return false
        }
    }

    /// Decodes a P1–P7, `PF` or `Pf` image into an sRGB `CGImage`.
    public static func decode(_ data: Data) throws -> CGImage {
        var scanner = ByteScanner([UInt8](data))
        let magic = try scanner.token()
        switch magic {
        case "P1": return try decodeBitmapASCII(&scanner)
        case "P4": return try decodeBitmapBinary(&scanner)
        case "P2": return try decodeGrayASCII(&scanner)
        case "P5": return try decodeGrayBinary(&scanner)
        case "P3": return try decodeColorASCII(&scanner)
        case "P6": return try decodeColorBinary(&scanner)
        case "P7": return try decodePAM(&scanner)
        case "Pf": return try decodePFM(&scanner, channels: 1)
        case "PF": return try decodePFM(&scanner, channels: 3)
        default: throw NetpbmError.notNetpbm
        }
    }

    /// Encodes an image as binary PPM (`P6`), PGM (`P5`) or PFM (`Pf`/`PF`),
    /// chosen from the image: float samples → PFM, grayscale → PGM, else PPM.
    public static func encode(_ image: CGImage) throws -> Data {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else {
            throw NetpbmError.encodeFailed("The image has no pixels.")
        }
        let isFloat = image.bitsPerComponent >= 32 || image.bitmapInfo.contains(.floatComponents)
        let isGray = image.colorSpace?.model == .monochrome

        if isFloat {
            let rgba = try floats(image)
            return isGray ? try encodePFMGray(rgba, width: width, height: height)
                          : try encodePFMColor(rgba, width: width, height: height)
        }

        let sixteenBit = image.bitsPerComponent >= 16
        if isGray {
            let words = try graySamples(image, sixteenBit: sixteenBit)
            return encodePGM(words, maxval: sixteenBit ? 65535 : 255, width: width, height: height)
        }
        let words = try colorSamples(image, sixteenBit: sixteenBit)
        return encodePPM(words, maxval: sixteenBit ? 65535 : 255, width: width, height: height)
    }

    // MARK: - Header helpers

    private static func dimensions(_ scanner: inout ByteScanner) throws -> (Int, Int, Int) {
        let width = try scanner.int()
        let height = try scanner.int()
        let maxval = try scanner.int()
        guard width > 0, height > 0 else { throw NetpbmError.malformed("Non-positive dimensions.") }
        guard maxval >= 1, maxval <= 65535 else {
            throw NetpbmError.malformed("Maxval \(maxval) is out of range.")
        }
        return (width, height, maxval)
    }

    // MARK: - Bitmap (P1 / P4)

    private static func decodeBitmapASCII(_ scanner: inout ByteScanner) throws -> CGImage {
        let width = try scanner.int(), height = try scanner.int()
        guard width > 0, height > 0 else { throw NetpbmError.malformed("Non-positive dimensions.") }
        var samples = [UInt8](repeating: 255, count: width * height)
        for i in 0..<(width * height) {
            let v = try scanner.int()
            samples[i] = v == 0 ? 255 : 0
        }
        return try makeRGB8(expandGray(samples), width: width, height: height)
    }

    private static func decodeBitmapBinary(_ scanner: inout ByteScanner) throws -> CGImage {
        let width = try scanner.int(), height = try scanner.int()
        guard width > 0, height > 0 else { throw NetpbmError.malformed("Non-positive dimensions.") }
        scanner.consumeSeparator()
        let rowBytes = (width + 7) / 8
        var samples = [UInt8](repeating: 255, count: width * height)
        // Packed MSB-first rows, each padded to a byte boundary.
        let raw = try scanner.readBytes(height * rowBytes)
        for y in 0..<height {
            for x in 0..<width {
                let byte = raw[raw.startIndex + y * rowBytes + x / 8]
                let bit = (byte >> (7 - UInt8(x % 8))) & 1
                samples[y * width + x] = bit == 0 ? 255 : 0
            }
        }
        return try makeRGB8(expandGray(samples), width: width, height: height)
    }

    // MARK: - Gray (P2 / P5)

    private static func decodeGrayASCII(_ scanner: inout ByteScanner) throws -> CGImage {
        let (width, height, maxval) = try dimensions(&scanner)
        var values = [Int](repeating: 0, count: width * height)
        for i in 0..<values.count { values[i] = try scanner.int() }
        return try grayImage(values, maxval: maxval, width: width, height: height)
    }

    private static func decodeGrayBinary(_ scanner: inout ByteScanner) throws -> CGImage {
        let (width, height, maxval) = try dimensions(&scanner)
        scanner.consumeSeparator()
        var values = [Int](repeating: 0, count: width * height)
        if maxval < 256 {
            for i in 0..<values.count { values[i] = Int(try scanner.readByte()) }
        } else {
            for i in 0..<values.count { values[i] = Int(try scanner.readUInt16BE()) }
        }
        return try grayImage(values, maxval: maxval, width: width, height: height)
    }

    private static func grayImage(_ values: [Int], maxval: Int, width: Int, height: Int) throws -> CGImage {
        if maxval <= 255 {
            let g = values.map { UInt8(scaled($0, from: maxval, to: 255)) }
            return try makeRGB8(expandGray(g), width: width, height: height)
        }
        let g = values.map { UInt16(scaled($0, from: maxval, to: 65535)) }
        return try makeRGB16(expandGray16(g), width: width, height: height)
    }

    // MARK: - Color (P3 / P6)

    private static func decodeColorASCII(_ scanner: inout ByteScanner) throws -> CGImage {
        let (width, height, maxval) = try dimensions(&scanner)
        var values = [Int](repeating: 0, count: width * height * 3)
        for i in 0..<values.count { values[i] = try scanner.int() }
        return try colorImage(values, maxval: maxval, width: width, height: height)
    }

    private static func decodeColorBinary(_ scanner: inout ByteScanner) throws -> CGImage {
        let (width, height, maxval) = try dimensions(&scanner)
        scanner.consumeSeparator()
        var values = [Int](repeating: 0, count: width * height * 3)
        if maxval < 256 {
            for i in 0..<values.count { values[i] = Int(try scanner.readByte()) }
        } else {
            for i in 0..<values.count { values[i] = Int(try scanner.readUInt16BE()) }
        }
        return try colorImage(values, maxval: maxval, width: width, height: height)
    }

    private static func colorImage(_ values: [Int], maxval: Int, width: Int, height: Int) throws -> CGImage {
        if maxval <= 255 {
            let rgb = values.map { UInt8(scaled($0, from: maxval, to: 255)) }
            return try makeRGB8(rgb, width: width, height: height)
        }
        let rgb = values.map { UInt16(scaled($0, from: maxval, to: 65535)) }
        return try makeRGB16(rgb, width: width, height: height)
    }

    // MARK: - PAM (P7)

    private static func decodePAM(_ scanner: inout ByteScanner) throws -> CGImage {
        var width = 0, height = 0, depth = 0, maxval = 0
        while true {
            let key = try scanner.token()
            switch key {
            case "WIDTH": width = try scanner.int()
            case "HEIGHT": height = try scanner.int()
            case "DEPTH": depth = try scanner.int()
            case "MAXVAL": maxval = try scanner.int()
            case "TUPLTYPE": _ = try scanner.token()
            case "ENDHDR": break
            default: _ = try scanner.token()
            }
            if key == "ENDHDR" { break }
        }
        guard width > 0, height > 0 else { throw NetpbmError.malformed("Non-positive dimensions.") }
        guard depth == 1 || depth == 3 || depth == 4 else {
            throw NetpbmError.unsupported("PAM depth \(depth) is not supported.")
        }
        guard maxval >= 1, maxval <= 65535 else { throw NetpbmError.malformed("Maxval \(maxval) is out of range.") }
        scanner.consumeSeparator()

        let count = width * height * depth
        var values = [Int](repeating: 0, count: count)
        if maxval < 256 {
            for i in 0..<count { values[i] = Int(try scanner.readByte()) }
        } else {
            for i in 0..<count { values[i] = Int(try scanner.readUInt16BE()) }
        }

        // PAM has no place for alpha in a Netpbm image; keep the first three
        // channels (or gray) and drop any alpha channel.
        var rgb = [Int](repeating: 0, count: width * height * 3)
        for p in 0..<(width * height) {
            let base = p * depth
            if depth == 1 {
                rgb[p * 3] = values[base]; rgb[p * 3 + 1] = values[base]; rgb[p * 3 + 2] = values[base]
            } else {
                rgb[p * 3] = values[base]; rgb[p * 3 + 1] = values[base + 1]; rgb[p * 3 + 2] = values[base + 2]
            }
        }
        return try colorImage(rgb, maxval: maxval, width: width, height: height)
    }

    // MARK: - PFM (PF / Pf)

    private static func decodePFM(_ scanner: inout ByteScanner, channels: Int) throws -> CGImage {
        let width = try scanner.int(), height = try scanner.int()
        guard width > 0, height > 0 else { throw NetpbmError.malformed("Non-positive dimensions.") }
        let scale = try scanner.float()
        let littleEndian = scale < 0
        scanner.consumeSeparator()

        let count = width * height * channels
        var raw = [Float](repeating: 0, count: count)
        for i in 0..<count { raw[i] = try scanner.readFloat(littleEndian: littleEndian) }

        // PFM stores scanlines bottom-to-top.
        var rgba = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            let src = (height - 1 - y) * width
            for x in 0..<width {
                let d = (y * width + x) * 4
                if channels == 1 {
                    let v = raw[src + x]
                    rgba[d] = v; rgba[d + 1] = v; rgba[d + 2] = v
                } else {
                    rgba[d] = raw[(src + x) * 3]
                    rgba[d + 1] = raw[(src + x) * 3 + 1]
                    rgba[d + 2] = raw[(src + x) * 3 + 2]
                }
            }
        }
        return try makeRGBFloat(rgba, width: width, height: height)
    }

    // MARK: - Sample extraction (encode)

    private static func colorSamples(_ image: CGImage, sixteenBit: Bool) throws -> [UInt16] {
        let width = image.width, height = image.height
        let count = width * height * 3
        var out = [UInt16](repeating: 0, count: count)
        if sixteenBit {
            let rgba = try rgba16(image)
            for p in 0..<(width * height) {
                out[p * 3] = rgba[p * 4]; out[p * 3 + 1] = rgba[p * 4 + 1]; out[p * 3 + 2] = rgba[p * 4 + 2]
            }
        } else {
            let rgba = try rgba8(image)
            for p in 0..<(width * height) {
                out[p * 3] = UInt16(rgba[p * 4]); out[p * 3 + 1] = UInt16(rgba[p * 4 + 1]); out[p * 3 + 2] = UInt16(rgba[p * 4 + 2])
            }
        }
        return out
    }

    private static func graySamples(_ image: CGImage, sixteenBit: Bool) throws -> [UInt16] {
        if sixteenBit {
            return try gray16(image).map { $0 }
        }
        return try gray8(image).map { UInt16($0) }
    }

    private static func floats(_ image: CGImage) throws -> [Float] {
        let width = image.width, height = image.height
        let count = width * height * 4
        var out = [Float](repeating: 1, count: count)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            .union(.floatComponents).union(.byteOrder32Little)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 32, bytesPerRow: width * 16, space: space,
                                bitmapInfo: info.rawValue)
            ctx?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    private static func rgba8(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var out = [UInt8](repeating: 255, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    private static func rgba16(_ image: CGImage) throws -> [UInt16] {
        let width = image.width, height = image.height
        var out = [UInt16](repeating: 65535, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue).union(.byteOrder16Little)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 16, bytesPerRow: width * 8, space: space,
                                bitmapInfo: info.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    private static func gray8(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var out = [UInt8](repeating: 0, count: width * height)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    private static func gray16(_ image: CGImage) throws -> [UInt16] {
        let width = image.width, height = image.height
        var out = [UInt16](repeating: 0, count: width * height)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue).union(.byteOrder16Little)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                bitsPerComponent: 16, bytesPerRow: width * 2, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: info.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    // MARK: - Writers

    private static func encodePGM(_ words: [UInt16], maxval: Int, width: Int, height: Int) -> Data {
        var data = header(magic: "P5", width: width, height: height, maxval: maxval)
        appendSamples(words, maxval: maxval, to: &data)
        return data
    }

    private static func encodePPM(_ words: [UInt16], maxval: Int, width: Int, height: Int) -> Data {
        var data = header(magic: "P6", width: width, height: height, maxval: maxval)
        appendSamples(words, maxval: maxval, to: &data)
        return data
    }

    private static func encodePFMGray(_ rgba: [Float], width: Int, height: Int) throws -> Data {
        var data = header(magic: "Pf", width: width, height: height, maxvalScale: -1.0)
        appendPFM(rgba, channels: 1, width: width, height: height, to: &data)
        return data
    }

    private static func encodePFMColor(_ rgba: [Float], width: Int, height: Int) throws -> Data {
        var data = header(magic: "PF", width: width, height: height, maxvalScale: -1.0)
        appendPFM(rgba, channels: 3, width: width, height: height, to: &data)
        return data
    }

    private static func header(magic: String, width: Int, height: Int, maxval: Int) -> Data {
        Data("\(magic)\n\(width) \(height)\n\(maxval)\n".utf8)
    }

    private static func header(magic: String, width: Int, height: Int, maxvalScale: Double) -> Data {
        Data("\(magic)\n\(width) \(height)\n\(maxvalScale)\n".utf8)
    }

    private static func appendSamples(_ words: [UInt16], maxval: Int, to data: inout Data) {
        if maxval < 256 {
            data.reserveCapacity(data.count + words.count)
            for w in words { data.append(UInt8(w)) }
        } else {
            data.reserveCapacity(data.count + words.count * 2)
            for w in words {
                data.append(UInt8(w >> 8))
                data.append(UInt8(w & 0xff))
            }
        }
    }

    private static func appendPFM(_ rgba: [Float], channels: Int, width: Int, height: Int, to data: inout Data) {
        data.reserveCapacity(data.count + width * height * channels * 4)
        // Bottom-to-top scanlines, little-endian floats.
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width {
                let base = (y * width + x) * 4
                let values = channels == 1 ? [rgba[base]] : [rgba[base], rgba[base + 1], rgba[base + 2]]
                for v in values {
                    var bits = v.bitPattern.littleEndian
                    withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
                }
            }
        }
    }

    // MARK: - Image construction

    private static func makeRGB8(_ rgb: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(rgb) as CFData) else {
            throw NetpbmError.malformed("Could not allocate sample data.")
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                  bytesPerRow: width * 3, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw NetpbmError.malformed("Could not build an 8-bit image.")
        }
        return image
    }

    private static func makeRGB16(_ rgb: [UInt16], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: rawData(rgb) as CFData) else {
            throw NetpbmError.malformed("Could not allocate sample data.")
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue).union(.byteOrder16Little)
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
                                  bytesPerRow: width * 6, space: space, bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw NetpbmError.malformed("Could not build a 16-bit image.")
        }
        return image
    }

    private static func makeRGBFloat(_ rgba: [Float], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: rawData(rgba) as CFData) else {
            throw NetpbmError.malformed("Could not allocate sample data.")
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
            .union(.floatComponents).union(.byteOrder32Little)
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 32, bitsPerPixel: 128,
                                  bytesPerRow: width * 16, space: space, bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw NetpbmError.malformed("Could not build a float image.")
        }
        return image
    }

    private static func rawData<T>(_ values: [T]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Scaling

    private static func scaled(_ value: Int, from maxval: Int, to target: Int) -> Int {
        if maxval == target { return value }
        return (value * target + maxval / 2) / maxval
    }

    private static func expandGray(_ gray: [UInt8]) -> [UInt8] {
        var rgb = [UInt8](repeating: 0, count: gray.count * 3)
        for i in 0..<gray.count {
            rgb[i * 3] = gray[i]; rgb[i * 3 + 1] = gray[i]; rgb[i * 3 + 2] = gray[i]
        }
        return rgb
    }

    private static func expandGray16(_ gray: [UInt16]) -> [UInt16] {
        var rgb = [UInt16](repeating: 0, count: gray.count * 3)
        for i in 0..<gray.count {
            rgb[i * 3] = gray[i]; rgb[i * 3 + 1] = gray[i]; rgb[i * 3 + 2] = gray[i]
        }
        return rgb
    }
}

/// Tokenizes a Netpbm header. Netpbm separates header fields with arbitrary
/// whitespace and comments (`#` to end of line); binary rasters follow a single
/// separator byte.
private struct ByteScanner {
    let bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    static func isSpace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0B || b == 0x0C
    }

    mutating func skipSpaceAndComments() {
        while index < bytes.count {
            let b = bytes[index]
            if ByteScanner.isSpace(b) { index += 1; continue }
            if b == UInt8(ascii: "#") {
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
                continue
            }
            break
        }
    }

    mutating func token() throws -> String {
        skipSpaceAndComments()
        let start = index
        while index < bytes.count {
            let b = bytes[index]
            if ByteScanner.isSpace(b) || b == UInt8(ascii: "#") { break }
            index += 1
        }
        guard index > start else { throw NetpbmError.malformed("Expected a header token.") }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func int() throws -> Int {
        let token = try token()
        guard let value = Int(token) else {
            throw NetpbmError.malformed("Expected an integer, found \"\(token)\".")
        }
        return value
    }

    mutating func float() throws -> Float {
        let token = try token()
        guard let value = Float(token) else {
            throw NetpbmError.malformed("Expected a number, found \"\(token)\".")
        }
        return value
    }

    /// Consumes the single whitespace separating the header from a binary raster.
    mutating func consumeSeparator() {
        if index < bytes.count, ByteScanner.isSpace(bytes[index]) {
            if bytes[index] == 0x0D, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                index += 2
            } else {
                index += 1
            }
        }
    }

    mutating func readByte() throws -> UInt8 {
        guard index < bytes.count else { throw NetpbmError.malformed("Truncated raster data.") }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func readUInt16BE() throws -> UInt16 {
        let high = try readByte(), low = try readByte()
        return UInt16(high) << 8 | UInt16(low)
    }

    mutating func readFloat(littleEndian: Bool) throws -> Float {
        let b0 = try readByte(), b1 = try readByte(), b2 = try readByte(), b3 = try readByte()
        let bits: UInt32 = littleEndian
            ? UInt32(b0) | UInt32(b1) << 8 | UInt32(b2) << 16 | UInt32(b3) << 24
            : UInt32(b0) << 24 | UInt32(b1) << 16 | UInt32(b2) << 8 | UInt32(b3)
        return Float(bitPattern: bits)
    }

    mutating func readBytes(_ count: Int) throws -> ArraySlice<UInt8> {
        guard index + count <= bytes.count else { throw NetpbmError.malformed("Truncated raster data.") }
        defer { index += count }
        return bytes[index..<(index + count)]
    }
}
