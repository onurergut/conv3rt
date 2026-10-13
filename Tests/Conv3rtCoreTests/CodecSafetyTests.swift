import XCTest
import CoreGraphics
import Darwin
@testable import Conv3rtCore

final class CodecSafetyTests: XCTestCase {
    private let marker: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]

    func testQOIRejectsMissingChunks() {
        XCTAssertThrowsError(try QOICodec.decode(qoi(chunks: [])))
    }

    func testQOIRejectsInvalidEndMarker() {
        var data = qoi(chunks: [0xC0])
        data[data.count - 1] = 0
        XCTAssertThrowsError(try QOICodec.decode(data))
    }

    func testQOIRejectsOverlongRunsAndExtraChunks() {
        XCTAssertThrowsError(try QOICodec.decode(qoi(chunks: [0xC1])))
        XCTAssertThrowsError(try QOICodec.decode(qoi(chunks: [0xC0, 0xC0])))
    }

    func testQOIChunkOperandsCannotConsumeEndMarker() {
        XCTAssertThrowsError(try QOICodec.decode(qoi(chunks: [0xFF])))
        XCTAssertThrowsError(try QOICodec.decode(qoi(chunks: [0xFE])))
        XCTAssertThrowsError(try QOICodec.decode(qoi(chunks: [0x80])))
    }

    func testQOIRejectsInvalidColorSpace() {
        var data = qoi(chunks: [0xC0])
        data[13] = 2
        XCTAssertThrowsError(try QOICodec.decode(data))
    }

    func testPAMPreservesRGBA8AndRGBA16Samples() throws {
        var eight = Data("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\nTUPLTYPE RGB_ALPHA\nENDHDR\n".utf8)
        eight.append(contentsOf: [24, 96, 192, 64])
        let image8 = try NetpbmCodec.decode(eight)
        XCTAssertEqual(image8.alphaInfo, .last)
        XCTAssertEqual(providerBytes(image8), [24, 96, 192, 64])

        var sixteen = Data("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 65535\nTUPLTYPE RGB_ALPHA\nENDHDR\n".utf8)
        sixteen.append(contentsOf: [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        let image16 = try NetpbmCodec.decode(sixteen)
        XCTAssertEqual(image16.bitsPerComponent, 16)
        XCTAssertEqual(image16.alphaInfo, .last)
        XCTAssertEqual(providerBytes(image16), [0x34, 0x12, 0x78, 0x56, 0xBC, 0x9A, 0xF0, 0xDE])
    }

    func testNetpbmRejectsSamplesOutsideDeclaredRange() throws { try runProbe("netpbm-binary-samples") }

    func testPFMRejectsInvalidScale() {
        for scale in ["0", "nan", "inf", "-inf"] {
            var data = Data("Pf\n1 1\n\(scale)\n".utf8)
            data.append(contentsOf: [0, 0, 0, 0])
            XCTAssertThrowsError(try NetpbmCodec.decode(data), scale)
        }
    }

    // Each probe runs in a child XCTest process because the original bugs trap.
    func testPCXRejectsShortScanlineWithoutCrashing() throws { try runProbe("pcx-stride") }
    func testPCXRejectsUnrepresentableEncoderDimensions() throws { try runProbe("pcx-height"); try runProbe("pcx-width") }
    func testPCXRejectsUnknownPlanesInsteadOfDiscardingSamples() {
        var bytes = [UInt8](repeating: 0, count: 132)
        bytes[0] = 0x0A; bytes[2] = 1; bytes[3] = 8
        bytes[65] = 4; bytes[66] = 1
        bytes[128] = 1; bytes[129] = 2; bytes[130] = 3; bytes[131] = 4
        XCTAssertThrowsError(try PCXCodec.decode(Data(bytes)))
    }
    func testPCXTinyTruncatedRasterDoesNotAllocateHeaderSizedBuffer() throws {
        try runProbe("pcx-tiny-raster", memoryLimit: 128 * 1024 * 1024)
    }
    func testPCXIndexedPaletteCannotSupplyMissingRasterBytes() {
        var bytes = [UInt8](repeating: 0, count: 128 + 769)
        bytes[0] = 0x0A; bytes[2] = 1; bytes[3] = 8
        bytes[65] = 1; bytes[66] = 1; bytes[128] = 0x0C
        XCTAssertThrowsError(try PCXCodec.decode(Data(bytes)))
    }
    func testNetpbmRejectsOverflowingDimensionsWithoutCrashing() throws { try runProbe("netpbm-overflow") }
    func testNetpbmRejectsInvalidASCIISamplesWithoutCrashing() throws { try runProbe("netpbm-samples") }
    func testPDFRejectsInvalidDPIAndFrameIndexWithoutCrashing() throws { try runProbe("pdf-dpi") }
    func testSVGRejectsInvalidScaleWithoutRendering() throws { try runProbe("svg-scale") }

    func testCrashProbe() throws {
        guard let probe = ProcessInfo.processInfo.environment["CONV3RT_CODEC_SAFETY_PROBE"] else { return }
        switch probe {
        case "pcx-stride":
            var data = [UInt8](repeating: 0, count: 131)
            data[0] = 0x0A; data[2] = 1; data[3] = 8
            data[8] = 1; data[65] = 3; data[66] = 1
            XCTAssertThrowsError(try PCXCodec.decode(Data(data)))
        case "pcx-height":
            let image = Fixtures.nonPremultiplied(rawRGBA: [UInt8](repeating: 255, count: 65537 * 4), width: 1, height: 65537)
            XCTAssertThrowsError(try PCXCodec.encode(image))
        case "pcx-width":
            let image = Fixtures.nonPremultiplied(rawRGBA: [UInt8](repeating: 255, count: 65535 * 4), width: 65535, height: 1)
            XCTAssertThrowsError(try PCXCodec.encode(image))
        case "pcx-tiny-raster":
            // The valid dimensions request ~2 GiB of RGBA storage, but the
            // three raster bytes cannot possibly encode its scanlines.
            var bytes = [UInt8](repeating: 0, count: 131)
            bytes[0] = 0x0A; bytes[2] = 1; bytes[3] = 8
            bytes[8] = 0xFF; bytes[9] = 0x7C // width 32000
            bytes[10] = 0x7F; bytes[11] = 0x3E // height 16000
            bytes[65] = 3; bytes[66] = 0x00; bytes[67] = 0x7D
            XCTAssertThrowsError(try PCXCodec.decode(Data(bytes)))
            var usage = rusage()
            XCTAssertEqual(getrusage(RUSAGE_SELF, &usage), 0)
            XCTAssertLessThanOrEqual(usage.ru_maxrss, 128 * 1024 * 1024,
                                     "A tiny rejected raster must not expand its header dimensions.")
        case "netpbm-overflow":
            for magic in ["P1", "P2", "P3", "P4", "P5", "P6", "Pf", "PF"] {
                let suffix = ["P1", "P4"].contains(magic) ? "" : (["Pf", "PF"].contains(magic) ? "-1\n" : "255\n")
                XCTAssertThrowsError(try NetpbmCodec.decode(Data("\(magic)\n\(Int.max) 2\n\(suffix)".utf8)), magic)
            }
            XCTAssertThrowsError(try NetpbmCodec.decode(Data("P7\nWIDTH \(Int.max)\nHEIGHT 2\nDEPTH 4\nMAXVAL 255\nENDHDR\n".utf8)))
        case "netpbm-samples":
            for sample in ["-1", "256", "\(Int.max)"] {
                XCTAssertThrowsError(try NetpbmCodec.decode(Data("P2\n1 1\n255\n\(sample)\n".utf8)))
                XCTAssertThrowsError(try NetpbmCodec.decode(Data("P3\n1 1\n255\n\(sample) 0 0\n".utf8)))
            }
        case "netpbm-binary-samples":
            XCTAssertThrowsError(try NetpbmCodec.decode(Data("P1\n1 1\n2\n".utf8)))
            var gray = Data("P5\n1 1\n1\n".utf8)
            gray.append(2)
            XCTAssertThrowsError(try NetpbmCodec.decode(gray))
            var color = Data("P6\n1 1\n1\n".utf8)
            color.append(contentsOf: [0, 1, 2])
            XCTAssertThrowsError(try NetpbmCodec.decode(color))
            var pam = Data("P7\nWIDTH 1\nHEIGHT 1\nDEPTH 3\nMAXVAL 1\nENDHDR\n".utf8)
            pam.append(contentsOf: [0, 1, 2])
            XCTAssertThrowsError(try NetpbmCodec.decode(pam))
        case "pdf-dpi":
            let dir = TempDir()
            let url = try Fixtures.pdfFixture(directory: dir.url)
            for dpi: CGFloat in [.nan, .infinity, .greatestFiniteMagnitude, 100_000, 0, -1] {
                XCTAssertNil(PDFFrameProvider(url: url, dpi: dpi))
            }
            let provider = try XCTUnwrap(PDFFrameProvider(url: url))
            XCTAssertTrue(provider.properties(at: -1).isEmpty)
            XCTAssertNil(provider.image(at: -1))
        case "svg-scale":
            let dir = TempDir()
            // NSImage loading is exercised with a raster fixture as well: the
            // scale guard must precede any renderer for accepted image content.
            let url = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png", directory: dir.url)
            XCTAssertNotNil(SVGFrameProvider(url: url))
            for scale: CGFloat in [.nan, .infinity, .greatestFiniteMagnitude, 100_000, 0, -1] {
                XCTAssertNil(SVGFrameProvider(url: url, scale: scale))
            }
        default: XCTFail("Unknown safety probe.")
        }
    }

    private func runProbe(_ probe: String, memoryLimit: UInt64? = nil) throws {
        let dir = TempDir()
        let log = dir.url.appendingPathComponent("probe.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xctest", "-XCTest", "Conv3rtCoreTests.CodecSafetyTests/testCrashProbe", Bundle(for: Self.self).bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["CONV3RT_CODEC_SAFETY_PROBE"] = probe
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        if let memoryLimit {
            while process.isRunning {
                var usage = rusage_info_v2()
                let result = withUnsafeMutablePointer(to: &usage) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(process.processIdentifier, RUSAGE_INFO_V2, $0)
                    }
                }
                if result == 0, usage.ri_resident_size > memoryLimit {
                    process.terminate()
                    XCTFail("A tiny rejected raster exceeded its child-process memory budget.")
                    break
                }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        process.waitUntilExit()
        let logText = try String(contentsOf: log, encoding: .utf8)
        XCTAssertEqual(process.terminationStatus, 0, "Probe \(probe) failed: \(String(logText.prefix(1600)))")
        XCTAssertTrue(logText.contains("Executed 1 test"), "The child must execute its regression.")
    }

    private func qoi(chunks: [UInt8]) -> Data {
        Data([0x71, 0x6F, 0x69, 0x66, 0, 0, 0, 1, 0, 0, 0, 1, 4, 0] + chunks + marker)
    }

    private func providerBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data else { return [] }
        return Array(Data(referencing: data))
    }
}
