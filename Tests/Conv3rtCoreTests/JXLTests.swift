#if CONV3RT_JXL
import XCTest
import ImageIO
@testable import Conv3rtCore

/// JPEG XL writing via the bundled libjxl. Compiled only when libjxl has been
/// built (scripts/build-jxl.sh).
final class JXLTests: XCTestCase {

    private let inspector = ImageInspector()
    private let planner = ConversionPlanner()
    private let registry = CapabilityRegistry.shared
    private func target(_ id: String) -> FormatCapability { registry.capability(id: id)! }

    func testJXLIsWritableWhenBuilt() {
        XCTAssertTrue(target("jxl").canWrite)
    }

    func testPNGtoJXLLosslessIsSampleExact() throws {
        let dir = TempDir()
        let src = try Fixtures.write(Fixtures.manyColors(), uti: "public.png", ext: "png",
                                     directory: dir.url, name: "src")
        let info = try inspector.inspect(url: src)

        let plan = planner.plan(source: info, target: target("jxl"),
                                settings: ConversionSettings(mode: .lossless))
        XCTAssertTrue(plan.isConvertible, plan.summary)

        let result = try ConversionEngine().convert(plan: plan, outputDirectory: dir.url,
                                                    namer: OutputNamer(), target: target("jxl"))
        let out = result.outputs[0]
        XCTAssertTrue(inspector.isReadable(url: out))

        let a = try Fixtures.rawRGBA(of: src)
        let b = try Fixtures.rawRGBA(of: out)
        XCTAssertEqual(a.width, b.width)
        XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.bytes, b.bytes, "Lossless JPEG XL must preserve every sample")
    }
}
#endif
