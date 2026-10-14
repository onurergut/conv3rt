import XCTest
import ImageIO
@testable import Conv3rtCore

/// Track E: writing an animation into a single file for the bundled codecs.
///
/// WebP animation is written through libwebp's mux animation encoder. JPEG XL
/// animation is not offered: libjxl can encode it, but macOS Image I/O cannot
/// read animated JPEG XL back (it reports a single frame), so the output could
/// not be verified — see `AnimationWriteTests.testJXLAnimationIsNotOffered`.
final class AnimationWriteTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    // MARK: - WebP

    func testAnimatedGIFToWebPKeepsAllFrames() throws {
        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 3)
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.isAnimated, "Fixture should inspect as animated")
        XCTAssertEqual(info.frameCount, 3)

        XCTAssertTrue(target("webp").supportsAnimation, "WebP write path now supports animation")

        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertTrue(plan.isConvertible, plan.summary)
        XCTAssertFalse(plan.expandsFramesOrPages, "An animated WebP is one file, not one per frame")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("webp"))
        XCTAssertEqual(result.outputs.count, 1, "One animated file")
        let out = result.outputs[0]
        XCTAssertTrue(inspector.isReadable(url: out))

        // Reopen the output. Image I/O (and the frame provider built on it)
        // reports the frame count directly.
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 3,
                       "The animated WebP must carry all 3 frames")

        let provider = try XCTUnwrap(SourceProviderFactory.make(url: out))
        XCTAssertTrue(provider.isAnimated, "Reopened WebP should be recognized as animated")
        XCTAssertGreaterThan(provider.frameCount, 1)
        XCTAssertEqual(provider.frameCount, 3, "Same frame count as the source")
    }

    func testAnimatedGIFToWebPPreservesTotalDuration() throws {
        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 3)  // 0.1 s per frame
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .highestQuality))
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("webp"))
        let out = try XCTUnwrap(result.outputs.first)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        var total = 0.0
        for i in 0..<CGImageSourceGetCount(source) {
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] ?? [:]
            if let webp = props[kCGImagePropertyWebPDictionary] as? [CFString: Any],
               let d = (webp[kCGImagePropertyWebPDelayTime] as? NSNumber)?.doubleValue {
                total += d
            }
        }
        XCTAssertEqual(total, 0.3, accuracy: 0.05,
                       "3 × 0.1 s of timing should be preserved")
    }

    func testSingleFrameGIFToWebPStillSingleFrame() throws {
        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 1)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .highestQuality))
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("webp"))
        let out = try XCTUnwrap(result.outputs.first)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1, "A still source stays a still WebP")
    }

    func testInspectorReportsAnimatedWebPSource() throws {
        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 3)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("webp"),
                                settings: ConversionSettings(mode: .highestQuality))
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("webp"))
        // The inspector must see the produced animated WebP as animated, so an
        // animated WebP used as a *source* later is never silently reduced.
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertTrue(outInfo.isAnimated, "An animated WebP source must inspect as animated")
        XCTAssertEqual(outInfo.frameCount, 3)
    }

    // MARK: - JPEG XL

    /// JPEG XL animation is deliberately not offered: macOS Image I/O reads an
    /// animated JPEG XL as a single frame, so a verified single-file animated
    /// output is not possible. Animated sources are split into per-frame files
    /// instead (documented behaviour).
    func testJXLAnimationIsNotOffered() throws {
        try XCTSkipUnless(JXLEncoder.isAvailable, "JPEG XL codec is not built in this environment")
        XCTAssertFalse(target("jxl").supportsAnimation,
                       "Animated JPEG XL is not offered (Image I/O cannot read it back)")

        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 3)
        let info = try inspector.inspect(url: src)

        // Default (undecided) policy blocks: the target cannot hold the frames.
        let blocked = planner.plan(source: info, target: target("jxl"),
                                   settings: ConversionSettings(mode: .highestQuality, framePolicy: .undecided))
        XCTAssertEqual(blocked.status, .blocked)

        // Export-all splits the animation into one file per frame.
        let split = planner.plan(source: info, target: target("jxl"),
                                 settings: ConversionSettings(mode: .highestQuality, framePolicy: .exportAll))
        XCTAssertTrue(split.isConvertible, split.summary)
        XCTAssertTrue(split.expandsFramesOrPages)

        let result = try ConversionEngine().convert(plan: split, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("jxl"))
        XCTAssertEqual(result.outputs.count, 3)
    }
}
