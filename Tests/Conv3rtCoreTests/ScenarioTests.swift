import XCTest
import ImageIO
@testable import Conv3rtCore

/// Scenarios that the product spec calls out explicitly.
final class ScenarioTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    // MARK: - Multipage

    func testMultipageTIFFtoPNGRequiresFrameDecision() throws {
        let dir = TempDir()
        let src = try Fixtures.multipageTIFF(directory: dir.url, pages: 2)
        let info = try inspector.inspect(url: src)
        XCTAssertEqual(info.pageCount, 2, "Fixture should report 2 pages")

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless, framePolicy: .undecided))
        XCTAssertEqual(plan.status, .blocked)
        XCTAssertTrue(plan.blockingChanges.contains { $0.code == "frames.decisionRequired" })
    }

    func testMultipageExportAllSplitsIntoFiles() throws {
        let dir = TempDir()
        let src = try Fixtures.multipageTIFF(directory: dir.url, pages: 3)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        XCTAssertTrue(plan.isConvertible)
        XCTAssertTrue(plan.expandsFramesOrPages)

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        XCTAssertEqual(result.outputs.count, 3, "Each page becomes its own file")
        for url in result.outputs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(inspector.isReadable(url: url))
        }
    }

    func testFirstPageOnlyInLosslessIsBlocked() throws {
        let dir = TempDir()
        let src = try Fixtures.multipageTIFF(directory: dir.url, pages: 2)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless, framePolicy: .firstOnly))
        XCTAssertEqual(plan.status, .blocked, "Discarding pages is not lossless")
    }

    // MARK: - Animation

    func testAnimatedGIFtoPNGUnsupportedTargetOffersOptions() throws {
        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 3)
        let info = try inspector.inspect(url: src)
        XCTAssertTrue(info.isAnimated || info.frameCount == 3, "Fixture should be animated")

        let undecided = planner.plan(source: info, target: target("png"),
                                     settings: ConversionSettings(mode: .lossless, framePolicy: .undecided))
        XCTAssertEqual(undecided.status, .blocked)

        let all = planner.plan(source: info, target: target("png"),
                               settings: ConversionSettings(mode: .lossless, framePolicy: .exportAll))
        XCTAssertTrue(all.isConvertible)
    }

    func testAnimatedGIFtoGIFPreservesFrames() throws {
        let dir = TempDir()
        let src = try Fixtures.animatedGIF(directory: dir.url, frames: 3)
        let info = try inspector.inspect(url: src)
        let plan = planner.plan(source: info, target: target("gif"),
                                settings: ConversionSettings(mode: .highestQuality, framePolicy: .undecided))
        XCTAssertFalse(plan.expandsFramesOrPages, "GIF target keeps frames in one file")

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("gif"))
        XCTAssertEqual(result.outputs.count, 1)
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertEqual(outInfo.frameCount, 3, "All frames should survive a GIF→GIF copy")
    }

    // MARK: - Bit depth

    func test16BitSourceDepthIsVisibleAndGuarded() throws {
        let dir = TempDir()
        let src = try Fixtures.gray16PNG(directory: dir.url)
        let info = try inspector.inspect(url: src)
        XCTAssertEqual(info.bitsPerComponent, 16, "Fixture should be 16-bit")

        // PNG→PNG lossless keeps 16-bit: ready, no depth warning.
        let pngPlan = planner.plan(source: info, target: target("png"),
                                   settings: ConversionSettings(mode: .lossless))
        XCTAssertFalse(pngPlan.changes.contains { $0.code == "depth.reduced" },
                       "16-bit PNG→PNG must not reduce depth")

        // 16-bit → JPEG (8-bit) in lossless must be blocked, not silent.
        let jpegPlan = planner.plan(source: info, target: target("jpeg"),
                                    settings: ConversionSettings(mode: .lossless))
        XCTAssertEqual(jpegPlan.status, .blocked)
        XCTAssertTrue(jpegPlan.blockingChanges.contains { $0.code == "depth.reduced" })
    }

    // MARK: - Orientation

    func testExifOrientationMetadataIsPreserved() throws {
        let dir = TempDir()
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,  // 90° CW
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "rotated"] as [CFString: Any],
        ]
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "oriented", properties: props)
        let info = try inspector.inspect(url: src)
        XCTAssertEqual(info.exifOrientation, 6)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .lossless, metadataPolicy: .keep))
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("png"))
        let outInfo = try inspector.inspect(url: result.outputs[0])
        XCTAssertEqual(outInfo.exifOrientation, 6, "Orientation tag must survive")
    }

    // MARK: - Mixed batch partial success

    func testMixedBatchProducesPartialSuccess() async throws {
        let dir = TempDir()
        let out = TempDir()
        let ok = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                    directory: dir.url, name: "ok")
        // A PNG with alpha cannot go to JPEG in lossless → this job is not planned.
        let alpha = try Fixtures.write(Fixtures.rgbaSample(), uti: "public.png", ext: "png",
                                       directory: dir.url, name: "alpha")

        let okInfo = try inspector.inspect(url: ok)
        let alphaInfo = try inspector.inspect(url: alpha)
        let okPlan = planner.plan(source: okInfo, target: target("png"),
                                  settings: ConversionSettings(mode: .lossless))
        let alphaPlan = planner.plan(source: alphaInfo, target: target("jpeg"),
                                     settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(okPlan.status.isConvertible)
        XCTAssertEqual(alphaPlan.status, .blocked)

        let jobs = [
            ConversionJob(source: ok, info: okInfo, plan: okPlan),
            ConversionJob(source: alpha, info: alphaInfo, plan: alphaPlan),
        ]
        // The runner only receives convertible jobs; blocked ones stay out.
        let convertible = jobs.filter { $0.plan.status.isConvertible }
        XCTAssertEqual(convertible.count, 1)

        let runner = BatchRunner()
        var succeeded = 0, failed = 0
        for await event in runner.run(jobs: convertible, outputDirectory: out.url) {
            if case .succeeded = event.state { succeeded += 1 }
            if case .failed = event.state { failed += 1 }
        }
        XCTAssertEqual(succeeded, 1)
        XCTAssertEqual(failed, 0)
    }
}
