import Foundation
import ImageIO

/// Reopens a written file and confirms it is a valid image of the expected type
/// with the expected frame count and non-zero dimensions. This is what makes a
/// job "successful" — not the encoder's finalize call alone.
///
/// It reopens through the same provider layer as the rest of the core, so
/// formats Image I/O cannot read (QOI, PCX, PFM) still verify via the bundled
/// decoders.
public struct OutputVerifier: Sendable {

    public init() {}

    public func verify(url: URL, expectedUTI: String, expectedFrames: Int) throws {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0 else {
            throw ConversionError.verificationFailed("The output file is empty.")
        }

        let actualUTI: String
        var frameCount = 1
        let kind = SourceProviderFactory.detectKind(url: url)

        if kind == .qoi || kind == .pcx || kind == .pfm {
            // Our own codecs: Image I/O mis-types some of these (e.g. PFM as
            // pbm), so verify through the provider layer.
            guard let provider = SourceProviderFactory.make(url: url),
                  let image = provider.image(at: 0) else {
                throw ConversionError.verificationFailed("The output has no recognizable image type.")
            }
            actualUTI = SourceProviderFactory.uti(for: kind) ?? expectedUTI
            frameCount = provider.frameCount
            if image.width == 0 || image.height == 0 {
                throw ConversionError.verificationFailed("The output image has zero dimensions.")
            }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let uti = CGImageSourceGetType(source) as String?,
                  CGImageSourceGetCount(source) > 0 {
            actualUTI = uti
            frameCount = CGImageSourceGetCount(source)
            if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
                let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
                if w == 0 || h == 0 {
                    throw ConversionError.verificationFailed("The output image has zero dimensions.")
                }
            }
        } else if kind == .pdf || kind == .svg,
                  let provider = SourceProviderFactory.make(url: url),
                  let image = provider.image(at: 0), image.width > 0, image.height > 0 {
            actualUTI = SourceProviderFactory.uti(for: kind) ?? expectedUTI
            frameCount = provider.frameCount
        } else {
            throw ConversionError.verificationFailed("The output has no recognizable image type.")
        }

        if !UTTypeBridge.conformance(actualUTI, toIdentifier: expectedUTI) && actualUTI != expectedUTI {
            throw ConversionError.verificationFailed("The output was written as \(actualUTI), not \(expectedUTI).")
        }
        if expectedFrames > 1 && frameCount < expectedFrames {
            throw ConversionError.verificationFailed("Expected \(expectedFrames) frames but found \(frameCount).")
        }
    }
}
