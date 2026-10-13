import Foundation
import Conv3rtCore

/// Headless diagnostics for development and CI. Runs before the SwiftUI run
/// loop; if a recognized flag is present it prints a report and exits.
enum Diagnostics {

    static func handleIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--dump-capabilities") {
            dumpCapabilities()
            exit(0)
        }
        if args.contains("--dump-json") {
            dumpJSON()
            exit(0)
        }
        if args.contains("--dump-matrix") {
            dumpMatrix()
            exit(0)
        }
        if let i = args.firstIndex(of: "--bench") {
            let count = (i + 1 < args.count) ? (Int(args[i + 1]) ?? 1000) : 1000
            Bench.run(count: count)
            exit(0)
        }
    }

    /// Emits the format matrix as Markdown, generated from the live registry so
    /// the documentation can never drift from the running code.
    static func dumpMatrix() {
        let caps = CapabilityRegistry.shared.capabilities()
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        func yn(_ b: Bool) -> String { b ? "yes" : "—" }
        print("| Format | UTI | Read | Write | Alpha | Anim | Pages | Metadata | Lossless | Provider | Evidence |")
        print("|---|---|---|---|---|---|---|---|---|---|---|")
        for c in caps {
            print("| \(c.displayName) | `\(c.uti)` | \(yn(c.canRead)) | \(yn(c.canWrite)) | "
                + "\(yn(c.supportsAlpha)) | \(yn(c.supportsAnimation)) | \(yn(c.supportsMultiPage)) | "
                + "\(yn(c.supportsMetadata)) | \(yn(c.hasLosslessPath)) | \(c.provider.rawValue) | \(c.evidence.rawValue) |")
        }
    }

    static func dumpCapabilities() {
        let snap = CapabilityRegistry.shared.snapshot()
        let caps = CapabilityRegistry.shared.capabilities()
        print("macOS \(snap.osVersion.majorVersion).\(snap.osVersion.minorVersion).\(snap.osVersion.patchVersion)  arch=\(snap.architecture)")
        print("readable types: \(snap.readableUTIs.count)   writable types: \(snap.writableUTIs.count)")
        print("")
        print(row("NAME", "READ", "WRITE", "ALPHA", "ANIM", "PAGES", "LOSSLESS"))
        for c in caps.sorted(by: { $0.displayName < $1.displayName }) {
            print(row(c.displayName, mark(c.canRead), mark(c.canWrite), mark(c.supportsAlpha),
                      mark(c.supportsAnimation), mark(c.supportsMultiPage), mark(c.hasLosslessPath)))
        }
    }

    static func dumpJSON() {
        // Simple line-oriented dump for scripting.
        for c in CapabilityRegistry.shared.capabilities().sorted(by: { $0.id < $1.id }) {
            print("\(c.id)\t\(c.uti)\tread=\(c.canRead)\twrite=\(c.canWrite)\text=\(c.fileExtensions.joined(separator: ","))")
        }
    }

    private static func mark(_ b: Bool) -> String { b ? "yes" : "-" }
    private static func pad(_ s: String, _ n: Int) -> String {
        s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count)
    }
    private static func row(_ name: String, _ a: String, _ b: String, _ c: String,
                            _ d: String, _ e: String, _ f: String) -> String {
        [pad(name, 24), pad(a, 6), pad(b, 6), pad(c, 6), pad(d, 6), pad(e, 6), pad(f, 6)]
            .joined(separator: " ")
    }
}
