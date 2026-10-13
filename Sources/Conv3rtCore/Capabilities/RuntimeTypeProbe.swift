import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Queries the operating system at runtime for the image types it can actually
/// read and write. A format appearing in a static list is never treated as
/// proof of support — this probe is the source of truth for availability.
public struct RuntimeTypeProbe: Sendable {

    public struct Snapshot: Sendable {
        public let readableUTIs: Set<String>
        public let writableUTIs: Set<String>
        public let osVersion: OperatingSystemVersion
        public let architecture: String
    }

    public init() {}

    public func snapshot() -> Snapshot {
        let readable = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return Snapshot(
            readableUTIs: Set(readable),
            writableUTIs: Set(writable),
            osVersion: ProcessInfo.processInfo.operatingSystemVersion,
            architecture: Self.architecture
        )
    }

    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Returns true when the runtime reports a writable destination for this UTI.
    public func canWrite(uti: String) -> Bool {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        return writable.contains(uti)
    }

    public func canRead(uti: String) -> Bool {
        let readable = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        return readable.contains(uti)
    }

    /// Resolves a UTI for a file extension, if the system knows one.
    public static func uti(forExtension ext: String) -> String? {
        UTType(filenameExtension: ext)?.identifier
    }
}
