import Foundation
import CoreGraphics
import PDFKit

/// Renders PDF pages to raster images at a chosen resolution.
///
/// The default render resolution is 144 DPI (a 2× device scale for a 72-DPI
/// PDF page), which balances fidelity and memory. This default is conv3rt's
/// choice, not a fixed product decision, and is documented as such.
public struct PDFFrameProvider: SourceFrameProvider {

    private let document: PDFDocument
    private let renderScale: CGFloat
    private let pageSizes: [CGSize]

    public let frameCount: Int
    public let unitName = "page"
    public let isAnimated = false

    /// - Parameter dpi: target render resolution; must be > 0.
    public init?(url: URL, dpi: CGFloat = 144) {
        guard dpi.isFinite, dpi > 0 else { return nil }
        guard let doc = PDFDocument(url: url) else { return nil }
        let count = doc.pageCount
        guard count > 0 else { return nil }
        let scale = dpi / 72.0
        let sizes = (0..<count).map { doc.page(at: $0)?.bounds(for: .mediaBox).size ?? .zero }
        var workspaceBytes = 0.0
        for size in sizes {
            guard let pixels = RasterSizeGuard.dimensions(size: size, scale: scale) else { return nil }
            workspaceBytes += Double(pixels.width) * Double(pixels.height) * 8
            guard workspaceBytes <= RasterSizeGuard.maximumBytes else { return nil }
        }
        self.document = doc
        self.renderScale = scale
        self.frameCount = count
        self.pageSizes = sizes
    }

    public func image(at index: Int) -> CGImage? {
        guard index >= 0, index < frameCount, let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard let pixels = RasterSizeGuard.dimensions(size: bounds.size, scale: renderScale) else { return nil }
        let pixelWidth = pixels.width, pixelHeight = pixels.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: renderScale, y: renderScale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    func inspection(at index: Int) -> FrameInspection? {
        guard index >= 0, index < pageSizes.count,
              let pixels = RasterSizeGuard.dimensions(size: pageSizes[index], scale: renderScale) else { return nil }
        return FrameInspection(width: pixels.width, height: pixels.height,
                               bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels.width * 4,
                               hasAlpha: true, colorSpaceName: CGColorSpace.sRGB as String)
    }

    public func properties(at index: Int) -> [CFString: Any] {
        guard index >= 0, index < pageSizes.count,
              let pixels = RasterSizeGuard.dimensions(size: pageSizes[index], scale: renderScale) else { return [:] }
        return [
            kCGImagePropertyPixelWidth: pixels.width,
            kCGImagePropertyPixelHeight: pixels.height,
        ]
    }
}

extension PDFFrameProvider: InspectableFrameProvider {}
