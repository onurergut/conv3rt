import Foundation
import CoreGraphics

/// Uniform access to the frames/pages of a source, regardless of what decodes
/// them (Image I/O, PDFKit, an SVG rasterizer, …).
public protocol SourceFrameProvider {
    /// Number of frames or pages available.
    var frameCount: Int { get }
    /// Human label for what a frame represents: "frame" or "page".
    var unitName: String { get }
    /// Decodes the frame at `index`. Returns nil on failure.
    func image(at index: Int) -> CGImage?
    /// Image I/O style property dictionary for the frame (may be empty).
    func properties(at index: Int) -> [CFString: Any]
    /// Whether the source is animated (has per-frame timing).
    var isAnimated: Bool { get }
}

protocol InspectableFrameProvider: SourceFrameProvider {
    func inspection(at index: Int) -> FrameInspection?
}

struct FrameInspection {
    let width: Int
    let height: Int
    let bitsPerComponent: Int
    let bitsPerPixel: Int
    let bytesPerRow: Int
    let hasAlpha: Bool
    let colorSpaceName: String?

    init(width: Int, height: Int, bitsPerComponent: Int, bitsPerPixel: Int,
         bytesPerRow: Int, hasAlpha: Bool, colorSpaceName: String?) {
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerPixel
        self.bytesPerRow = bytesPerRow
        self.hasAlpha = hasAlpha
        self.colorSpaceName = colorSpaceName
    }

    init(image: CGImage) {
        width = image.width
        height = image.height
        bitsPerComponent = image.bitsPerComponent
        bitsPerPixel = image.bitsPerPixel
        bytesPerRow = image.bytesPerRow
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly: hasAlpha = true
        default: hasAlpha = false
        }
        colorSpaceName = image.colorSpace?.name as String?
    }
}
