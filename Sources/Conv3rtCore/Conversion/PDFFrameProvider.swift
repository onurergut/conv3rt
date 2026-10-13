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
        guard let doc = PDFDocument(url: url) else { return nil }
        let count = doc.pageCount
        guard count > 0 else { return nil }
        self.document = doc
        self.renderScale = max(dpi, 1) / 72.0
        self.frameCount = count
        self.pageSizes = (0..<count).map { doc.page(at: $0)?.bounds(for: .mediaBox).size ?? .zero }
    }

    public func image(at index: Int) -> CGImage? {
        guard let page = document.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let pixelWidth = max(Int((bounds.width * renderScale).rounded()), 1)
        let pixelHeight = max(Int((bounds.height * renderScale).rounded()), 1)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: renderScale, y: renderScale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    public func properties(at index: Int) -> [CFString: Any] {
        guard index < pageSizes.count else { return [:] }
        let size = pageSizes[index]
        return [
            kCGImagePropertyPixelWidth: Int((size.width * renderScale).rounded()),
            kCGImagePropertyPixelHeight: Int((size.height * renderScale).rounded()),
        ]
    }
}
