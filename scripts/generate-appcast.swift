#!/usr/bin/env swift
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let files = FileManager.default

struct GenerationError: Error, CustomStringConvertible {
    let description: String
}

func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw GenerationError(description: message) }
}

func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
}

func versionNumbers(_ value: String, componentCount: ClosedRange<Int>) throws -> [UInt64] {
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    try require(componentCount.contains(components.count), "Invalid version: \(value)")
    return try components.map {
        try require(matches(String($0), "^(0|[1-9][0-9]*)$"), "Invalid version: \(value)")
        guard let number = UInt64($0) else { throw GenerationError(description: "Version component too large") }
        return number
    }
}

func buildNumber(_ value: String) throws -> UInt64 {
    try require(matches(value, "^[1-9][0-9]*$"), "Build must be a positive integer")
    guard let build = UInt64(value) else { throw GenerationError(description: "Build too large") }
    return build
}

func validSignature(_ value: String) -> Bool {
    guard let decoded = Data(base64Encoded: value), decoded.count == 64 else { return false }
    return decoded.base64EncodedString() == value
}

func releaseURL(_ value: String, version: String, label: String) throws {
    guard let url = URLComponents(string: value) else { throw GenerationError(description: "Invalid asset URL") }
    try require(url.scheme == "https" && url.host == "github.com" && url.port == nil &&
                url.user == nil && url.password == nil && url.query == nil && url.fragment == nil,
                "Asset URL must be unauthenticated HTTPS on github.com without port, query or fragment")
    let prefix = "/onurergut/conv3rt/releases/download/"
    let path = url.percentEncodedPath
    try require(path.hasPrefix(prefix), "Asset URL must belong to onurergut/conv3rt Releases")
    let parts = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
    try require(parts.count == 2 && (parts[0] == version || parts[0] == "v\(version)") &&
                parts[1] == "conv3rt-\(version)-\(label).zip",
                "Asset URL tag, version or architecture differs from archive")
    try require(value == "https://github.com\(path)", "Asset URL must use canonical HTTPS form")
}

func xml(_ data: Data) throws -> XMLDocument {
    let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
    try require(document.dtd == nil, "Appcast must not contain a DTD")
    return document
}

func text(_ name: String, _ value: String) -> XMLElement {
    XMLElement(name: name, stringValue: value)
}

func attribute(_ name: String, _ value: String) -> XMLNode {
    XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
}

struct Tools {
    let temporary: URL

    // File-backed output avoids deadlocks from a verifier filling a pipe.
    func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let output = temporary.appendingPathComponent(UUID().uuidString)
        try Data().write(to: output)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close(); try? files.removeItem(at: output) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        process.waitUntilExit()
        try require(process.terminationReason == .exit && process.terminationStatus == 0,
                    "\(executable.lastPathComponent) failed (exit \(process.terminationStatus)); feed unchanged")
        guard let result = String(data: try Data(contentsOf: output), encoding: .utf8) else {
            throw GenerationError(description: "Invalid tool output encoding")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func digest(_ url: URL) throws -> String {
        let result = try run(URL(fileURLWithPath: "/usr/bin/shasum"), ["-a", "256", url.path])
        guard let digest = result.split(separator: " ").first, matches(String(digest), "^[0-9a-f]{64}$") else {
            throw GenerationError(description: "Invalid archive checksum output")
        }
        return String(digest)
    }
}

struct Metadata {
    let version: String
    let numbers: [UInt64]
    let build: String
    let buildValue: UInt64
    let minimumOS: String
    let publicKey: String

    init(app: URL, arch: String) throws {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw GenerationError(description: "Archived Info.plist is not a dictionary")
        }
        func string(_ key: String) throws -> String {
            guard let value = plist[key] as? String, !value.isEmpty else {
                throw GenerationError(description: "Missing archived plist string: \(key)")
            }
            return value
        }
        try require(try string("CFBundleIdentifier") == "com.conv3rt.app", "Archive is not conv3rt")
        version = try string("CFBundleShortVersionString")
        numbers = try versionNumbers(version, componentCount: 3...3)
        build = try string("CFBundleVersion")
        buildValue = try buildNumber(build)
        minimumOS = try string("LSMinimumSystemVersion")
        _ = try versionNumbers(minimumOS, componentCount: 2...3)
        try require(try string("SUFeedURL") ==
                    "https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-\(arch).xml",
                    "Archived app uses wrong architecture feed")
        publicKey = try string("SUPublicEDKey")
        try require(Data(base64Encoded: publicKey)?.count == 32, "Invalid archived Sparkle public key")
    }
}

func validateHistory(_ channel: XMLElement, metadata: Metadata, label: String) throws {
    var previousBuild: UInt64?
    var previousVersion: [UInt64]?
    for item in channel.elements(forName: "item") {
        func value(_ name: String) throws -> String {
            let nodes = item.elements(forName: name)
            try require(nodes.count == 1 && nodes[0].stringValue != nil, "Missing or ambiguous feed field: \(name)")
            return nodes[0].stringValue!
        }
        let build = try buildNumber(value("sparkle:version"))
        let version = try value("sparkle:shortVersionString")
        let numbers = try versionNumbers(version, componentCount: 3...3)
        _ = try versionNumbers(value("sparkle:minimumSystemVersion"), componentCount: 2...3)
        let enclosures = item.elements(forName: "enclosure")
        try require(enclosures.count == 1, "Feed item must have exactly one enclosure")
        let enclosure = enclosures[0]
        try releaseURL(enclosure.attribute(forName: "url")?.stringValue ?? "", version: version, label: label)
        try require(validSignature(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue ?? ""),
                    "Invalid existing enclosure signature")
        try require(UInt64(enclosure.attribute(forName: "length")?.stringValue ?? "") ?? 0 > 0 &&
                    enclosure.attribute(forName: "type")?.stringValue == "application/octet-stream",
                    "Invalid existing enclosure length or type")
        try require(metadata.buildValue > build, "New build must be greater than every existing build")
        try require(!metadata.numbers.lexicographicallyPrecedes(numbers), "New version must not downgrade existing version")
        if let previousBuild, let previousVersion {
            try require(previousBuild > build && !previousVersion.lexicographicallyPrecedes(numbers),
                        "Existing feed is not strictly newest-first")
        }
        previousBuild = build
        previousVersion = numbers
    }
}

func generate() throws {
    let usage = "Usage: swift scripts/generate-appcast.swift --archive <final-notarized.zip> --asset-url <GitHub-Release-HTTPS-URL> --arch <arm64|x86_64> --account <Sparkle-Keychain-account> [--title <text>]"
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] { print(usage); return }
    var options: [String: String] = [:]
    var index = 0
    while index < arguments.count {
        let name = arguments[index]
        try require(["--archive", "--asset-url", "--arch", "--account", "--title"].contains(name) && index + 1 < arguments.count,
                    usage)
        options[name] = arguments[index + 1]
        index += 2
    }
    func option(_ name: String) throws -> String {
        guard let value = options[name], !value.isEmpty else { throw GenerationError(description: "Missing \(name). \(usage)") }
        return value
    }
    let arch = try option("--arch")
    try require(arch == "arm64" || arch == "x86_64", "Architecture must be arm64 or x86_64")
    let label = arch == "arm64" ? "apple-silicon" : "intel"
    let asset = try option("--asset-url")
    let account = try option("--account")
    try require(matches(account, "^[A-Za-z0-9._-]+$") && account != "ed25519", "Use an explicit app-specific Sparkle Keychain account")
    let archive = URL(fileURLWithPath: try option("--archive")).standardizedFileURL
    let resource = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    try require(resource.isRegularFile == true && resource.isSymbolicLink != true && (resource.fileSize ?? 0) > 0 &&
                archive.pathExtension == "zip", "Archive must be a nonempty regular ZIP file")
    let feed = root.appendingPathComponent("updates/appcast-\(arch).xml")
    let originalFeed = try Data(contentsOf: feed)
    let document = try xml(originalFeed)
    guard let rss = document.rootElement(), rss.name == "rss", rss.attribute(forName: "version")?.stringValue == "2.0",
          rss.namespace(forPrefix: "sparkle")?.stringValue == sparkleNamespace,
          rss.elements(forName: "channel").count == 1 else {
        throw GenerationError(description: "Invalid RSS feed or Sparkle namespace")
    }
    let channel = rss.elements(forName: "channel")[0]
    let temporary = files.temporaryDirectory.appendingPathComponent("conv3rt-appcast-\(UUID().uuidString)")
    try files.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? files.removeItem(at: temporary) }
    let tools = Tools(temporary: temporary)
    let originalDigest = try tools.digest(archive)
    let stagedArchive = temporary.appendingPathComponent(archive.lastPathComponent)
    try files.copyItem(at: archive, to: stagedArchive)
    func unchanged() throws {
        try require(try tools.digest(archive) == originalDigest && tools.digest(stagedArchive) == originalDigest,
                    "Archive bytes changed during generation; feed unchanged")
    }
    try unchanged()
    let entries = try tools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-Z1", stagedArchive.path])
    for entry in entries.split(separator: "\n") {
        let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
        try require(!entry.hasPrefix("/") && !parts.contains("..") && !entry.contains("\\") &&
                    (entry.hasPrefix("conv3rt.app/") || entry.hasPrefix("__MACOSX/")),
                    "Archive contains unexpected or unsafe paths")
    }
    _ = try tools.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", stagedArchive.path, temporary.path])
    let app = temporary.appendingPathComponent("conv3rt.app")
    let metadata = try Metadata(app: app, arch: arch)
    try require(archive.lastPathComponent == "conv3rt-\(metadata.version)-\(label).zip", "Archive filename differs from version or architecture")
    try releaseURL(asset, version: metadata.version, label: label)
    try validateHistory(channel, metadata: metadata, label: label)
    try (originalDigest + "\n").write(to: stagedArchive.appendingPathExtension("sha256"), atomically: true, encoding: .utf8)

    // Release mode only: the verifier checks signatures, architecture and stapled notarization.
    _ = try tools.run(URL(fileURLWithPath: "/bin/bash"),
                      [root.appendingPathComponent("scripts/verify-release.sh").path, app.path, metadata.version, arch, "release", metadata.build])
    try unchanged()
    let bin = root.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin")
    let key = try tools.run(bin.appendingPathComponent("generate_keys"), ["--account", account, "-p"])
    try require(key == metadata.publicKey, "Signing account public key differs from archived SUPublicEDKey")
    let signer = bin.appendingPathComponent("sign_update")
    let signed = try tools.run(signer, ["--account", account, stagedArchive.path])
    let signingXML = try xml(Data("<enclosure xmlns:sparkle=\"\(sparkleNamespace)\" \(signed)/>".utf8))
    guard let signedEnclosure = signingXML.rootElement(), signedEnclosure.name == "enclosure",
          signedEnclosure.attributes?.count == 2, (signedEnclosure.children ?? []).isEmpty,
          let signature = signedEnclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
          let length = signedEnclosure.attribute(forName: "length")?.stringValue else {
        throw GenerationError(description: "Malformed sign_update signature/length output")
    }
    try require(validSignature(signature), "sign_update did not return a canonical 64-byte EdDSA signature")
    let size = try stagedArchive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    try require(length == String(size), "sign_update length differs from exact ZIP byte count")
    try unchanged()
    _ = try tools.run(signer, ["--account", account, "--verify", stagedArchive.path, signature])
    try unchanged()

    let item = XMLElement(name: "item")
    item.addChild(text("title", options["--title"] ?? "conv3rt \(metadata.version)"))
    let date = DateFormatter()
    date.locale = Locale(identifier: "en_US_POSIX")
    date.timeZone = TimeZone(secondsFromGMT: 0)
    date.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    item.addChild(text("pubDate", date.string(from: Date())))
    item.addChild(text("sparkle:version", metadata.build))
    item.addChild(text("sparkle:shortVersionString", metadata.version))
    item.addChild(text("sparkle:minimumSystemVersion", metadata.minimumOS))
    let enclosure = XMLElement(name: "enclosure")
    enclosure.attributes = [attribute("url", asset), attribute("length", length), attribute("type", "application/octet-stream"),
                            attribute("sparkle:edSignature", signature)]
    item.addChild(enclosure)
    channel.insertChild(item, at: channel.elements(forName: "item").first?.index ?? channel.childCount)
    channel.elements(forName: "description").first?.stringValue = "Stable conv3rt updates for \(arch)."
    document.characterEncoding = "UTF-8"
    let output = document.xmlData(options: [.nodePrettyPrint])
    _ = try xml(output)
    try require(try Data(contentsOf: feed) == originalFeed, "Feed changed concurrently; rerun generation")
    try unchanged()
    try output.write(to: feed, options: .atomic)
    print("Prepared \(feed.lastPathComponent): \(metadata.version) build \(metadata.build), \(length) signed ZIP bytes. Nothing published.")
}

do {
    try generate()
} catch {
    FileHandle.standardError.write(Data("Appcast generation failed: \(error)\n".utf8))
    exit(1)
}
