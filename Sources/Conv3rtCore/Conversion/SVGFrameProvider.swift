import Foundation
import AppKit
import CoreGraphics

/// Rasterizes a static SVG using AppKit's built-in renderer (`NSImage`).
///
/// This is a device-local, offline path: no script execution, no remote
/// resource or font downloads. It produces a *rasterized* image — it is not a
/// vector-to-raster lossless operation, and conv3rt labels it as structural.
public final class SVGFrameProvider: SourceFrameProvider {

    private let rendered: CGImage
    public let frameCount = 1
    public let unitName = "frame"
    public let isAnimated = false

    /// - Parameter scale: multiplier over the SVG's intrinsic size.
    public init?(url: URL, scale: CGFloat = 2.0) {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var size = image.size
        if size.width < 1 || size.height < 1 { size = NSSize(width: 512, height: 512) }
        var rect = NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        self.rendered = cg
    }

    public func image(at index: Int) -> CGImage? {
        index == 0 ? rendered : nil
    }

    public func properties(at index: Int) -> [CFString: Any] {
        [
            kCGImagePropertyPixelWidth: rendered.width,
            kCGImagePropertyPixelHeight: rendered.height,
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
        ]
    }
}
