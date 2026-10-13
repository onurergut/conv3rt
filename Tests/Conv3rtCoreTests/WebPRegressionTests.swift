import XCTest
import CoreGraphics
import ImageIO
@testable import Conv3rtCore

final class WebPRegressionTests: XCTestCase {
    private let registry = CapabilityRegistry.shared

    func testWebPReportsEncodingProgressBeforeCompletion() throws {
        let source = TempDir(), output = TempDir()
        let url = try Fixtures.write(Fixtures.manyColors(width: 256, height: 256),
                                     uti: "public.png", ext: "png", directory: source.url)
        let target = try XCTUnwrap(registry.capability(id: "webp"))
        let plan = ConversionPlanner().plan(source: try ImageInspector().inspect(url: url),
                                            target: target, settings: ConversionSettings())
        let progress = ProgressCapture()
        let result = try ConversionEngine().convert(plan: plan, outputDirectory: output.url,
                                                    namer: OutputNamer(), target: target,
                                                    progress: { progress.record($0) })
        XCTAssertEqual(result.outputs.count, 1)
        XCTAssertTrue(progress.values.contains { $0 > 0 && $0 < 1 },
                      "A WebP conversion must show encoder progress while it is working")
    }

    func testCancelDuringWebPEncodingLeavesNoOutput() throws {
        let source = TempDir(), output = TempDir()
        let url = try Fixtures.write(Fixtures.manyColors(width: 256, height: 256),
                                     uti: "public.png", ext: "png", directory: source.url)
        let target = try XCTUnwrap(registry.capability(id: "webp"))
        let plan = ConversionPlanner().plan(source: try ImageInspector().inspect(url: url),
                                            target: target, settings: ConversionSettings())
        let token = CancelToken()
        XCTAssertThrowsError(try ConversionEngine().convert(
            plan: plan, outputDirectory: output.url, namer: OutputNamer(), target: target,
            isCancelled: { token.isCancelled }, progress: { p in
                if p > 0 && p < 1 { token.cancel() }
            })) { error in
                XCTAssertEqual(error as? ConversionError, .canceled)
            }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: output.url.path).isEmpty)
    }

    func testPremultipliedP3BufferHasStraightSamplesInSourceColorSpace() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                             bytesPerRow: 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 4)
        bytes[0] = 64; bytes[1] = 32; bytes[2] = 16; bytes[3] = 128
        let buffer = try RGBABuffer.tightlyPacked(from: XCTUnwrap(context.makeImage()))
        XCTAssertEqual(buffer.bytes, [128, 64, 32, 128])
        XCTAssertEqual(buffer.colorSpace, space)
    }

    func testLosslessVerifierDoesNotHideSixteenBitSampleChanges() throws {
        let source = TempDir(), output = TempDir()
        func write(_ value: UInt16, in directory: URL) throws -> URL {
            let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 16,
                                                 bytesPerRow: 2, space: CGColorSpaceCreateDeviceGray(),
                                                 bitmapInfo: CGImageAlphaInfo.none.rawValue
                                                    | CGBitmapInfo.byteOrder16Little.rawValue))
            try XCTUnwrap(context.data).bindMemory(to: UInt16.self, capacity: 1).pointee = value
            return try Fixtures.write(XCTUnwrap(context.makeImage()), uti: "public.png", ext: "png",
                                      directory: directory)
        }
        let sourceURL = try write(30000, in: source.url)
        let outputURL = try write(30001, in: output.url)
        let info = try ImageInspector().inspect(url: sourceURL)
        let provider = try XCTUnwrap(SourceProviderFactory.make(url: sourceURL))
        XCTAssertThrowsError(try LosslessVerifier().verify(sourceProvider: provider, sourceInfo: info,
                                                          sourceIndices: [0], outputURL: outputURL,
                                                          expectedOutputFrames: 1)) { error in
            guard case ConversionError.verificationFailed(let message) = error else {
                return XCTFail("Expected sample verification failure, got \(error)")
            }
            XCTAssertTrue(message.contains("samples differ"), message)
        }
    }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Double] = []
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return stored }
    func record(_ value: Double) { lock.lock(); stored.append(value); lock.unlock() }
}
