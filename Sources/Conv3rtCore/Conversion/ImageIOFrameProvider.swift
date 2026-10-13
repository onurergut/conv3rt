import Foundation
import ImageIO

/// Frame provider backed by Image I/O. Used for every format macOS decodes,
/// including RAW, PSD, HEIC, WebP, AVIF, JPEG XL, GIF, TIFF and friends.
public struct ImageIOFrameProvider: SourceFrameProvider {

    private let source: CGImageSource
    public let frameCount: Int
    public let unitName: String
    public let isAnimated: Bool

    public init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        self.source = source
        self.frameCount = CGImageSourceGetCount(source)
        let uti = CGImageSourceGetType(source) as String? ?? ""
        let animated = UTTypeBridge.conformance(uti, toIdentifier: "com.compuserve.gif")
            || UTTypeBridge.conformance(uti, toIdentifier: "public.heics")
        self.isAnimated = animated
        self.unitName = animated ? "frame" : (CGImageSourceGetCount(source) > 1 ? "page" : "frame")
    }

    public func image(at index: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateImageAtIndex(source, index, opts as CFDictionary)
    }

    public func properties(at index: Int) -> [CFString: Any] {
        (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
    }

    /// Container-level properties (first image), used as metadata defaults.
    public func containerProperties() -> [CFString: Any] {
        (CGImageSourceCopyProperties(source, nil) as? [CFString: Any]) ?? [:]
    }
}
