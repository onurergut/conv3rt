import Foundation
import Darwin

/// Manages a single write to the output folder via a temporary file.
///
/// Flow: encode into a hidden temp file in the destination folder, verify it,
/// then move it into place under a collision-free name. A partial or failed
/// write never leaves a file that looks like a successful output. Only files
/// conv3rt created (the temp file) are ever removed.
public final class SafeOutput {

    public let directory: URL
    public let tempURL: URL

    public init(directory: URL) throws {
        self.directory = directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw OutputError.folderUnavailable(directory.path)
        }
        self.tempURL = directory.appendingPathComponent(".conv3rt-\(UUID().uuidString).tmp")
    }

    /// Moves the encoded temp file to `finalURL`. If the destination now exists
    /// (concurrent writer), retries with a fresh collision-free name.
    @discardableResult
    public func commit(to finalURL: URL, namer: OutputNamer,
                       baseName: String, ext: String) throws -> URL {
        var destination = finalURL
        var attempts = 0
        while true {
            // FileManager's existence check and move can race another writer.
            // RENAME_EXCL tests and places the complete file atomically, even
            // when the destination is a dangling symbolic link.
            let status = tempURL.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    guard let source, let target else { errno = EINVAL; return Int32(-1) }
                    return renamex_np(source, target, UInt32(RENAME_EXCL))
                }
            }
            if status == 0 { return destination }
            let code = errno
            guard code == EEXIST else {
                if code == ENOSPC { throw OutputError.noSpace }
                if code == EACCES || code == EPERM { throw OutputError.notWritable(directory.path) }
                throw OutputError.writeFailed(String(cString: strerror(code)))
            }
            attempts += 1
            if attempts >= 50 { throw OutputError.writeFailed(String(cString: strerror(code))) }
            destination = namer.uniqueURL(in: directory, baseName: baseName, fileExtension: ext)
        }
    }

    /// Removes the temp file if it still exists. Never removes anything else.
    public func cleanup() {
        try? FileManager.default.removeItem(at: tempURL)
    }
}

public enum OutputError: Error, LocalizedError, Sendable {
    case folderUnavailable(String)
    case notWritable(String)
    case writeFailed(String)
    case noSpace

    public var errorDescription: String? {
        switch self {
        case .folderUnavailable: return "The output folder is unavailable. Choose another folder."
        case .notWritable(let p): return "conv3rt cannot write to \(p)."
        case .writeFailed(let d): return "The file could not be written. \(d)"
        case .noSpace: return "Not enough disk space to write the output."
        }
    }
}
