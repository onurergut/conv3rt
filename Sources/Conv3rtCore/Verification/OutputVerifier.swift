import Foundation
import ImageIO

/// Reopens a written file and confirms it is a valid image of the expected type
/// with the expected frame count and non-zero dimensions. This is what makes a
/// job "successful" — not the encoder's finalize call alone.
public struct OutputVerifier: Sendable {

    public init() {}

    public func verify(url: URL, expectedUTI: String, expectedFrames: Int) throws {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 0 else {
            throw ConversionError.verificationFailed("The output file is empty.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError.verificationFailed("The output could not be reopened.")
        }
        guard let uti = CGImageSourceGetType(source) as String? else {
            throw ConversionError.verificationFailed("The output has no recognizable image type.")
        }
        if !UTTypeBridge.conformance(uti, toIdentifier: expectedUTI) && uti != expectedUTI {
            throw ConversionError.verificationFailed("The output was written as \(uti), not \(expectedUTI).")
        }
        let count = CGImageSourceGetCount(source)
        guard count >= 1 else {
            throw ConversionError.verificationFailed("The output contains no images.")
        }
        // Multipage/animation: require at least the expected frames when the
        // container is meant to hold several.
        if expectedFrames > 1 && !isFramesSeparated(expectedUTI) && count < expectedFrames {
            throw ConversionError.verificationFailed("Expected \(expectedFrames) frames but found \(count).")
        }
        // Dimensions must be non-zero.
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            if w == 0 || h == 0 {
                throw ConversionError.verificationFailed("The output image has zero dimensions.")
            }
        }
    }

    /// True when the target format stores each frame as a separate file rather
    /// than in a multi-frame container (so a single frame per file is expected).
    private func isFramesSeparated(_ uti: String) -> Bool {
        false
    }
}
