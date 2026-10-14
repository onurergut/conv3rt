import Foundation
import CoreGraphics
import ImageIO

/// Decodes an IEEE 754 half-precision bit pattern to `Double` without the
/// `Float16` type, which Swift only provides on Apple silicon. Intel builds
/// need the same value to verify 16-bit float samples losslessly.
enum HalfFloat {
    static func decode(_ bits: UInt16) -> Double {
        let sign = UInt64(bits & 0x8000) << 48
        let exponent = UInt64(bits >> 10) & 0x1F
        let mantissa = UInt64(bits & 0x3FF)
        if exponent == 0x1F {
            return Double(bitPattern: sign | 0x7FF0_0000_0000_0000 | (mantissa << 42))
        }
        if exponent == 0 {
            if mantissa == 0 { return Double(bitPattern: sign) }
            var remainder = mantissa
            var shift: UInt64 = 0
            while remainder & 0x400 == 0 { remainder <<= 1; shift += 1 }
            let field = UInt64(1009 - Int(shift))
            return Double(bitPattern: sign | (field << 52) | ((remainder & 0x3FF) << 42))
        }
        return Double(bitPattern: sign | ((exponent + 1008) << 52) | (mantissa << 42))
    }
}

/// Confirms that a conversion the planner promised as **Lossless** really
/// preserved the decoded image: it re-decodes the output and compares it to the
/// source frame by frame. This is what makes "Lossless" a claim backed by
/// evidence rather than an encoder flag.
///
/// Compares samples at their decoded precision, including alpha and RGB under
/// transparent pixels. No 8-bit rendering is used during verification.
struct LosslessVerifier {

    func verify(sourceProvider: any SourceFrameProvider,
                sourceInfo: ImageInfo,
                sourceIndices: [Int],
                outputURL: URL,
                expectedOutputFrames: Int) throws {
        // Real transparency loss is caught by the per-sample RGBA comparison
        // below (a transparent pixel would compare differently); a fully opaque
        // image with an alpha channel may legitimately be stored without one.
        guard let outProvider = SourceProviderFactory.make(url: outputURL) else {
            throw ConversionError.verificationFailed("Lossless verification failed: output could not be reopened.")
        }
        guard outProvider.frameCount >= expectedOutputFrames else {
            throw ConversionError.verificationFailed(
                "Lossless verification failed: expected \(expectedOutputFrames) frames, found \(outProvider.frameCount).")
        }

        for (n, sourceIndex) in sourceIndices.enumerated() {
            guard let sourceImage = sourceProvider.image(at: sourceIndex),
                  let outputImage = outProvider.image(at: n) else {
                throw ConversionError.verificationFailed("Lossless verification failed: a frame could not be decoded.")
            }
            guard outputImage.bitsPerComponent >= sourceImage.bitsPerComponent else {
                throw ConversionError.verificationFailed("Lossless verification failed: bit depth was reduced.")
            }
            let profileName = sourceProvider.properties(at: sourceIndex)[kCGImagePropertyProfileName] as? String
            if profileName?.isEmpty == false,
               sourceImage.colorSpace?.copyICCData() != outputImage.colorSpace?.copyICCData() {
                throw ConversionError.verificationFailed("Lossless verification failed: color profile changed.")
            }
            let source = try Samples(image: sourceImage)
            let output = try Samples(image: outputImage)
            guard sourceImage.width == outputImage.width, sourceImage.height == outputImage.height,
                  source.colorComponents == output.colorComponents else {
                throw ConversionError.verificationFailed("Lossless verification failed: image dimensions or color model changed.")
            }
            for y in 0..<sourceImage.height {
                for x in 0..<sourceImage.width {
                    for component in 0...source.colorComponents {
                        if !source.matches(output, x: x, y: y, component: component) {
                            throw ConversionError.verificationFailed(
                                "Lossless verification failed: decoded samples differ (lossless was not preserved).")
                        }
                    }
                }
            }
            if sourceProvider.isAnimated, expectedOutputFrames > 1,
               let sourceDelay = SourceAnimation.duration(in: sourceProvider.properties(at: sourceIndex)),
               SourceAnimation.duration(in: outProvider.properties(at: n)) != sourceDelay {
                throw ConversionError.verificationFailed(
                    "Lossless verification failed: animation timing changed.")
            }
        }
        if sourceProvider.isAnimated, expectedOutputFrames > 1,
           let source = sourceProvider as? ImageIOFrameProvider,
           let output = outProvider as? ImageIOFrameProvider,
           source.animationLoopCount != output.animationLoopCount {
            throw ConversionError.verificationFailed("Lossless verification failed: animation loop count changed.")
        }
    }

    private struct Samples {
        let image: CGImage
        let data: CFData
        let colorComponents: Int
        let storedColorComponents: Int
        let palette: [UInt8]?
        let paletteComponents: Int
        let colorOffset: Int
        let alphaIndex: Int?
        let premultiplied: Bool
        let littleEndian: Bool
        let reversedPixel: Bool

        init(image: CGImage) throws {
            guard let space = image.colorSpace, let data = image.dataProvider?.data,
                  [1, 2, 4, 8, 16, 32].contains(image.bitsPerComponent) else {
                throw ConversionError.verificationFailed("Lossless verification failed: decoded sample layout is unsupported.")
            }
            let components: Int
            var palette: [UInt8]?
            var paletteComponents = 0
            switch space.model {
            case .rgb: components = 3
            case .monochrome: components = 1
            case .cmyk: components = 4
            case .indexed:
                guard let base = space.baseColorSpace,
                      base.model == .rgb || base.model == .monochrome,
                      let table = space.colorTable, !table.isEmpty else {
                    throw ConversionError.verificationFailed("Lossless verification failed: decoded palette is unsupported.")
                }
                components = 1
                palette = table
                paletteComponents = base.numberOfComponents
            default:
                throw ConversionError.verificationFailed("Lossless verification failed: decoded color model is unsupported.")
            }
            let stored = image.bitsPerPixel / image.bitsPerComponent
            let offset: Int
            let alpha: Int?
            let premultiplied: Bool
            switch image.alphaInfo {
            case .first, .premultipliedFirst:
                offset = 1; alpha = 0; premultiplied = image.alphaInfo == .premultipliedFirst
            case .last, .premultipliedLast:
                offset = 0; alpha = components; premultiplied = image.alphaInfo == .premultipliedLast
            case .noneSkipFirst:
                offset = 1; alpha = nil; premultiplied = false
            case .none, .noneSkipLast:
                offset = 0; alpha = nil; premultiplied = false
            default:
                throw ConversionError.verificationFailed("Lossless verification failed: decoded alpha layout is unsupported.")
            }
            let rowBytes = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
            guard !rowBytes.overflow, rowBytes.partialValue <= CFDataGetLength(data),
                  stored >= components + offset,
                  alpha == nil || stored > alpha! else {
                throw ConversionError.verificationFailed("Lossless verification failed: decoded sample storage is incomplete.")
            }
            self.image = image
            self.data = data
            self.colorComponents = components == 4 ? 4 : 3
            self.storedColorComponents = components
            self.palette = palette
            self.paletteComponents = paletteComponents
            self.colorOffset = offset
            self.alphaIndex = alpha
            self.premultiplied = premultiplied
            let order = image.bitmapInfo.intersection(.byteOrderMask)
            self.littleEndian = order.isEmpty || order == .byteOrder16Little || order == .byteOrder32Little
            self.reversedPixel = image.bitsPerComponent == 8 && stored == 4 && order == .byteOrder32Little
        }

        func value(x: Int, y: Int, component: Int) -> Double {
            let alpha = alphaIndex.map { rawValue(x: x, y: y, component: $0) } ?? 1
            if component == colorComponents { return alpha }
            let storedComponent = storedColorComponents == 1 ? 0 : component
            let value: Double
            if let palette {
                let maximum = Double((UInt64(1) << image.bitsPerComponent) - 1)
                let index = Int((rawValue(x: x, y: y, component: 0) * maximum).rounded())
                let offset = index * paletteComponents + (paletteComponents == 1 ? 0 : component)
                guard offset < palette.count else { return .nan }
                value = Double(palette[offset]) / 255
            } else {
                value = rawValue(x: x, y: y, component: colorOffset + storedComponent)
            }
            if premultiplied && alpha > 0 {
                if image.bitmapInfo.contains(.floatComponents) { return value / alpha }
                let maximum = Double((UInt64(1) << image.bitsPerComponent) - 1)
                return min(maximum, (value / alpha * maximum).rounded()) / maximum
            }
            return value
        }

        func matches(_ other: Samples, x: Int, y: Int, component: Int) -> Bool {
            let lhs = value(x: x, y: y, component: component)
            let rhs = other.value(x: x, y: y, component: component)
            if lhs == rhs { return true }
            guard lhs.isNaN, rhs.isNaN,
                  let lhsNaN = nanIdentity(x: x, y: y, component: component),
                  let rhsNaN = other.nanIdentity(x: x, y: y, component: component) else { return false }
            return lhsNaN == rhsNaN
        }

        /// Align the original sign and payload to binary64 without converting
        /// the NaN arithmetically: Float→Double can quiet a signaling NaN.
        private func nanIdentity(x: Int, y: Int, component: Int) -> UInt64? {
            guard image.bitmapInfo.contains(.floatComponents), palette == nil else { return nil }
            let storedComponent: Int
            if component == colorComponents {
                guard let alphaIndex else { return nil }
                storedComponent = alphaIndex
            } else {
                storedComponent = colorOffset + (storedColorComponents == 1 ? 0 : component)
            }
            let word = rawWord(x: x, y: y, component: storedComponent)
            switch image.bitsPerComponent {
            case 16:
                guard word & 0x7C00 == 0x7C00, word & 0x03FF != 0 else { return nil }
                return (word & 0x8000) << 48 | 0x7FF0_0000_0000_0000 | (word & 0x03FF) << 42
            case 32:
                guard word & 0x7F80_0000 == 0x7F80_0000, word & 0x007F_FFFF != 0 else { return nil }
                return (word & 0x8000_0000) << 32 | 0x7FF0_0000_0000_0000 | (word & 0x007F_FFFF) << 29
            default:
                return nil
            }
        }

        private func rawValue(x: Int, y: Int, component: Int) -> Double {
            let word = rawWord(x: x, y: y, component: component)
            let bits = image.bitsPerComponent
            if image.bitmapInfo.contains(.floatComponents) {
                if bits == 16 { return HalfFloat.decode(UInt16(word)) }
                return Double(Float(bitPattern: UInt32(word)))
            }
            return Double(word) / Double((UInt64(1) << bits) - 1)
        }

        private func rawWord(x: Int, y: Int, component: Int) -> UInt64 {
            let component = reversedPixel ? 3 - component : component
            let bits = image.bitsPerComponent
            let bitOffset = x * image.bitsPerPixel + component * bits
            let pointer = CFDataGetBytePtr(data)!
            let offset = y * image.bytesPerRow + bitOffset / 8
            let word: UInt64
            if bits < 8 {
                word = UInt64((pointer[offset] >> (8 - bits - bitOffset % 8)) & UInt8((1 << bits) - 1))
            } else {
                var value: UInt64 = 0
                for byte in 0..<(bits / 8) {
                    let shift = littleEndian ? byte * 8 : (bits / 8 - 1 - byte) * 8
                    value |= UInt64(pointer[offset + byte]) << shift
                }
                word = value
            }
            return word
        }
    }
}
