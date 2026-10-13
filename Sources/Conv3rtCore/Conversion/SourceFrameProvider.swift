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
