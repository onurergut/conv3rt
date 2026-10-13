import Foundation
import CoreGraphics
import ImageIO

/// Wraps a single already-decoded `CGImage` as a `SourceFrameProvider`. Used for
/// formats conv3rt decodes itself (QOI, PCX, PFM) that Image I/O cannot.
struct StaticImageProvider: SourceFrameProvider {
    let image: CGImage
    var frameCount: Int { 1 }
    let unitName = "frame"
    let isAnimated = false

    func image(at index: Int) -> CGImage? { index == 0 ? image : nil }

    func properties(at index: Int) -> [CFString: Any] {
        [
            kCGImagePropertyPixelWidth: image.width,
            kCGImagePropertyPixelHeight: image.height,
        ]
    }
}
