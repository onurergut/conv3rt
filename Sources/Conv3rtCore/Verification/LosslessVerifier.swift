import Foundation
import CoreGraphics

/// Confirms that a conversion the planner promised as **Lossless** really
/// preserved the decoded image: it re-decodes the output and compares it to the
/// source frame by frame. This is what makes "Lossless" a claim backed by
/// evidence rather than an encoder flag.
///
/// It uses the same RGBA extraction pipeline for both sides, so alpha and
/// transparent-pixel RGB are compared too.
struct LosslessVerifier {

    func verify(sourceProvider: any SourceFrameProvider,
                sourceInfo: ImageInfo,
                sourceIndices: [Int],
                outputURL: URL,
                expectedOutputFrames: Int) throws {
        let outInfo = try ImageInspector().inspect(url: outputURL)
        if outInfo.bitsPerComponent < sourceInfo.bitsPerComponent {
            throw ConversionError.verificationFailed(
                "Lossless verification failed: bit depth reduced from \(sourceInfo.bitsPerComponent) to \(outInfo.bitsPerComponent).")
        }
        // Real transparency loss is caught by the per-sample RGBA comparison
        // below (a transparent pixel would compare differently); a fully opaque
        // image with an alpha channel may legitimately be stored without one.
        guard let outProvider = SourceProviderFactory.make(url: outputURL) else {
            throw ConversionError.verificationFailed("Lossless verification failed: output could not be reopened.")
        }
        guard outProvider.frameCount >= expectedOutputFrames else {
            throw ConversionError.verificationFailed(
                "Lossless verification failed: expected \(expectedOutputFrames) frames, found \(outProvider.frameCount).")
        }

        for (n, sourceIndex) in sourceIndices.enumerated() {
            guard let sourceImage = sourceProvider.image(at: sourceIndex),
                  let outputImage = outProvider.image(at: n) else {
                throw ConversionError.verificationFailed("Lossless verification failed: a frame could not be decoded.")
            }
            let sb = try RGBABuffer.tightlyPacked(from: sourceImage)
            let ob = try RGBABuffer.tightlyPacked(from: outputImage)
            guard sb.width == ob.width, sb.height == ob.height, sb.bytes == ob.bytes else {
                throw ConversionError.verificationFailed(
                    "Lossless verification failed: decoded samples differ (lossless was not preserved).")
            }
        }
    }
}
