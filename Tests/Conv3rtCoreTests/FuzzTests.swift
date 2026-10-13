import XCTest
import ImageIO
@testable import Conv3rtCore

/// Deterministic robustness ("fuzz") tests.
///
/// No real randomness is used: a tiny seeded LCG produces the byte streams, so
/// every case is reproducible — a failure here reproduces exactly. The point is
/// not exhaustive coverage but a guarantee about malformed input: conv3rt must
/// always fail cleanly (throw / block), never crash, and never leave a partial
/// or otherwise unusable file in the output folder.
final class FuzzTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared

    private func target(_ id: String) -> FormatCapability {
        guard let t = registry.capability(id: id) else { fatalError("missing target \(id)") }
        return t
    }

    // MARK: - Deterministic pseudo-randomness

    /// A linear congruential generator. A fixed seed always yields the same
    /// stream, so these tests never flake.
    private struct LCG {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
        mutating func byte() -> UInt8 { UInt8(truncatingIfNeeded: next() >> 33) }
        mutating func bytes(_ count: Int) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: count)
            for i in 0..<count { out[i] = byte() }
            return out
        }
        /// A value in `0..<range` (0 when range is not positive).
        mutating func index(_ range: Int) -> Int { range <= 0 ? 0 : Int(next() % UInt64(range)) }
    }

    private let extensions = ["png", "jpg", "tiff", "bmp", "webp"]

    // MARK: - Pipeline helpers

    private enum Outcome {
        case threw
        case blocked
        case produced([URL])
    }

    /// Runs the real pipeline — inspect, plan, convert — and reports what it did.
    /// A malformed source must land in `.threw` or `.blocked`; `.produced` is
    /// only legitimate for input that is genuinely decodable.
    private func attemptConversion(source: URL, into outDir: URL) -> Outcome {
        do {
            let info = try inspector.inspect(url: source)
            let plan = planner.plan(source: info, target: target("png"),
                                    settings: ConversionSettings(mode: .highestQuality))
            if plan.status == .blocked { return .blocked }
            do {
                let result = try ConversionEngine().convert(plan: plan, outputDirectory: outDir,
                                                            namer: OutputNamer(), target: target("png"))
                return .produced(result.outputs)
            } catch {
                return .threw
            }
        } catch {
            return .threw
        }
    }

    private func directoryContents(_ dir: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    }

    private func write(_ bytes: [UInt8], to url: URL) throws {
        try Data(bytes).write(to: url)
    }

    // MARK: - Random bytes with image extensions

    func testRandomBytesAreNeverReadableAndInspectThrows() throws {
        let dir = TempDir()
        var rng = LCG(seed: 0xC0FF_EE00_C0FF_EE00)
        for ext in extensions {
            for i in 0..<6 {
                let url = dir.url.appendingPathComponent("fuzz-\(ext)-\(i).\(ext)")
                try write(rng.bytes(16 + rng.index(4096)), to: url)
                XCTAssertFalse(inspector.isReadable(url: url),
                               "\(url.lastPathComponent) must not be reported as readable")
                XCTAssertThrowsError(try inspector.inspect(url: url),
                                     "\(url.lastPathComponent) must throw, never crash")
            }
        }
    }

    func testRandomBytesConversionNeverLeavesAnOutput() throws {
        let src = TempDir()
        let out = TempDir()
        var rng = LCG(seed: 0xDEAD_BEEF_DEAD_BEEF)
        for ext in extensions {
            let url = src.url.appendingPathComponent("corrupt.\(ext)")
            try write(rng.bytes(256 + rng.index(4096)), to: url)

            let outcome = attemptConversion(source: url, into: out.url)
            if case .produced(let urls) = outcome {
                XCTFail("garbage .\(ext) unexpectedly produced \(urls.map(\.lastPathComponent))")
            }
            XCTAssertTrue(directoryContents(out.url).isEmpty,
                          "a rejected .\(ext) source must leave no output file")
        }
    }

    // MARK: - A planner+engine path that is forced to run on a corrupt file

    func testCorruptFilePlannedAsPNGStillFailsCleanlyWithoutOutput() throws {
        let src = TempDir()
        let out = TempDir()
        var rng = LCG(seed: 0x1234_5678_9ABC_DEF0)
        let url = src.url.appendingPathComponent("fake.png")
        try write(rng.bytes(512), to: url)

        // Pretend a detector believed this was a PNG, so the planner and engine
        // are exercised on a file that cannot actually be decoded.
        let info = ImageInfo(
            url: url, detectedUTI: "public.png", declaredUTI: "public.png", fileSize: 512,
            pixelWidth: 32, pixelHeight: 32, frameCount: 1, pageCount: 1,
            frameDurations: [], loopCount: nil, canvasWidth: 32, canvasHeight: 32,
            bitsPerComponent: 8, bitsPerPixel: 32, hasAlpha: true,
            colorModel: "RGB", colorSpaceName: "sRGB", hasColorProfile: true,
            exifOrientation: nil, hasEXIF: false, hasGPS: false, hasIPTC: false, hasXMP: false)

        let plan = planner.plan(source: info, target: target("png"),
                                settings: ConversionSettings(mode: .highestQuality))
        XCTAssertNotEqual(plan.status, .blocked,
                          "planning succeeds from metadata; the file itself is what fails")

        XCTAssertThrowsError(
            try ConversionEngine().convert(plan: plan, outputDirectory: out.url,
                                           namer: OutputNamer(), target: target("png")),
            "decoding a corrupt source must throw, never crash"
        )
        XCTAssertTrue(directoryContents(out.url).isEmpty,
                      "a failed conversion must leave no output file behind")
    }

    // MARK: - Valid PNG signature followed by random bytes

    /// Image I/O is lenient: it may accept a bare PNG signature as a source with
    /// a non-zero frame count, so "unreadable" is not the contract here. What we
    /// require is graceful degradation — inspection never crashes, and the
    /// pipeline either fails cleanly or produces a complete, readable file.
    func testPNGSignatureWithRandomPayloadDegradesGracefully() throws {
        let src = TempDir()
        let out = TempDir()
        // Decimal 137 80 78 71 13 10 26 10 — the PNG signature.
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        var rng = LCG(seed: 0xABCD_EF01_2345_6789)
        for i in 0..<8 {
            let url = src.url.appendingPathComponent("sig-\(i).png")
            try write(signature + rng.bytes(8 + rng.index(2048)), to: url)

            // Inspection must never crash: it either returns info or throws.
            _ = try? inspector.inspect(url: url)

            let outcome = attemptConversion(source: url, into: out.url)
            let remaining = directoryContents(out.url)
            switch outcome {
            case .threw, .blocked:
                XCTAssertTrue(remaining.isEmpty,
                              "a failed/blocked conversion must leave no output; found \(remaining)")
            case .produced(let urls):
                for output in urls {
                    XCTAssertTrue(inspector.isReadable(url: output),
                                  "any produced output must be a complete, readable file")
                }
            }
            XCTAssertFalse(remaining.contains { $0.hasPrefix(".conv3rt-") },
                           "no temporary file may remain, found \(remaining)")
        }
    }

    // MARK: - Byte-flipped real fixture must degrade gracefully

    func testByteFlippedFixtureDegradesGracefullyNeverHalfWritten() throws {
        let src = TempDir()
        let out = TempDir()
        let good = try Fixtures.write(Fixtures.manyColors(width: 32, height: 32),
                                      uti: "public.png", ext: "png", directory: src.url, name: "good")
        let original = try Data(contentsOf: good)

        var rng = LCG(seed: 0x5EED_1234_5678_9ABC)
        var corrupt = original
        // Corrupt bytes past the header/signature so the container is still
        // recognized but its pixel payload is damaged.
        for _ in 0..<12 {
            let idx = 16 + rng.index(max(original.count - 16, 1))
            corrupt[idx] = corrupt[idx] ^ UInt8(1 + rng.index(254))
        }
        let url = src.url.appendingPathComponent("flipped.png")
        try corrupt.write(to: url)

        // Inspection must never crash: it either returns info or throws.
        _ = try? inspector.inspect(url: url)

        // The pipeline must either fail cleanly or produce a complete output.
        let outcome = attemptConversion(source: url, into: out.url)
        let remaining = directoryContents(out.url)

        switch outcome {
        case .threw, .blocked:
            XCTAssertTrue(remaining.isEmpty,
                          "a failed/blocked conversion must leave no output; found \(remaining)")
        case .produced(let urls):
            for output in urls {
                XCTAssertTrue(inspector.isReadable(url: output),
                              "any produced output must be a complete, readable file")
            }
        }

        // In every case, no hidden temp file may survive.
        XCTAssertFalse(remaining.contains { $0.hasPrefix(".conv3rt-") },
                       "no temporary file may remain, found \(remaining)")
    }
}
