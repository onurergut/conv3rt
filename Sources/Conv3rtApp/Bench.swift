import Foundation
import CoreGraphics
import ImageIO
import Conv3rtCore

/// A development-only benchmark that produces real numbers for the size/speed/
/// memory report (spec section 24). Not part of normal use.
enum Bench {

    static func run(count: Int, size: Int = 256) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("conv3rt-bench-\(UUID().uuidString)")
        let src = root.appendingPathComponent("src")
        let out = root.appendingPathComponent("out")
        try? fm.createDirectory(at: src, withIntermediateDirectories: true)
        try? fm.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // 1. Generate synthetic PNGs.
        let genStart = Date()
        var totalBytes: Int64 = 0
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var urls: [URL] = []
        for i in 0..<count {
            guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.setFillColor(red: Double((i * 7) % 256) / 255, green: Double((i * 13) % 256) / 255,
                             blue: Double((i * 29) % 256) / 255, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            guard let img = ctx.makeImage() else { continue }
            let url = src.appendingPathComponent(String(format: "f%05d.png", i))
            if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, img, nil)
                if CGImageDestinationFinalize(dest) {
                    urls.append(url)
                    totalBytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                }
            }
        }
        let genSeconds = Date().timeIntervalSince(genStart)

        // 2. Inspect + plan (PNG -> TIFF, lossless).
        let registry = CapabilityRegistry.shared
        let inspector = ImageInspector()
        let planner = ConversionPlanner()
        guard let target = registry.capability(id: "tiff") else { return }
        let inspectStart = Date()
        var jobs: [ConversionJob] = []
        for url in urls {
            guard let info = try? inspector.inspect(url: url) else { continue }
            let plan = planner.plan(source: info, target: target,
                                    settings: ConversionSettings(mode: .lossless))
            jobs.append(ConversionJob(source: url, info: info, plan: plan))
        }
        let inspectSeconds = Date().timeIntervalSince(inspectStart)

        // 3. Convert, sampling memory.
        let runner = BatchRunner()
        let token = runner.currentToken
        var peakMB = 0.0
        let sem = DispatchSemaphore(value: 0)
        let convStart = Date()
        var done = 0, failed = 0
        Task {
            for await event in runner.run(jobs: jobs, outputDirectory: out, registry: registry) {
                if case .succeeded = event.state { done += 1 }
                if case .failed = event.state { failed += 1 }
                peakMB = max(peakMB, Self.footprintMB())
            }
            _ = token // keep alive
            sem.signal()
        }
        sem.wait()
        let convSeconds = Date().timeIntervalSince(convStart)

        let workers = BatchRunner.concurrency(for: jobs)
        print("conv3rt benchmark")
        print("  files:            \(jobs.count) PNG (\(size)×\(size)), \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)) total")
        print("  concurrency:      \(workers) workers")
        print("  generate:         \(fmt(genSeconds))")
        print("  inspect + plan:   \(fmt(inspectSeconds))")
        print("  convert (PNG→TIFF): \(fmt(convSeconds))  (\(String(format: "%.0f", Double(jobs.count) / max(convSeconds, 0.001))) files/s)")
        print("  succeeded/failed: \(done)/\(failed)")
        print("  peak memory:      \(String(format: "%.1f", peakMB)) MB")
        print("  memory start:     \(String(format: "%.1f", Self.footprintMB())) MB")
    }

    private static func fmt(_ s: Double) -> String { String(format: "%.3f s", s) }

    /// Current physical memory footprint of the process, in MB.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }
}
