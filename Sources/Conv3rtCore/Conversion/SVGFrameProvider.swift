import Foundation
import AppKit
import CoreGraphics

/// Rasterizes a static SVG using AppKit's built-in renderer (`NSImage`).
///
/// This is a device-local, offline path: no script execution, no remote
/// resource or font downloads. It produces a *rasterized* image — it is not a
/// vector-to-raster lossless operation, and conv3rt labels it as structural.
public final class SVGFrameProvider: SourceFrameProvider {

    private let source: NSImage
    private let proposedRect: NSRect
    private(set) var renderedImage: CGImage?
    public let frameCount = 1
    public let unitName = "frame"
    public let isAnimated = false

    /// - Parameter scale: multiplier over the SVG's intrinsic size.
    public init?(url: URL, scale: CGFloat = 2.0) {
        guard scale.isFinite, scale > 0 else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        var size = image.size
        guard size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0 else { return nil }
        if size.width < 1 || size.height < 1 { size = NSSize(width: 512, height: 512) }
        // NSImage may choose its intrinsic raster representation despite the
        // proposed rect, so both sizes must fit before asking it to render.
        guard RasterSizeGuard.dimensions(size: size, scale: 1) != nil,
              RasterSizeGuard.dimensions(size: size, scale: scale) != nil else { return nil }
        self.source = image
        self.proposedRect = NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
    }

    public func image(at index: Int) -> CGImage? {
        guard index == 0 else { return nil }
        if let renderedImage { return renderedImage }
        var rect = proposedRect
        guard let image = source.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              RasterSizeGuard.fits(width: image.width, height: image.height, bytesPerPixel: 8) else { return nil }
        renderedImage = image
        return image
    }

    public func properties(at index: Int) -> [CFString: Any] {
        guard let image = image(at: index) else { return [:] }
        return [
            kCGImagePropertyPixelWidth: image.width,
            kCGImagePropertyPixelHeight: image.height,
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
        ]
    }
}
