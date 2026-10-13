import Foundation

/// How serious a predicted change is.
public enum ChangeSeverity: Int, Codable, Comparable, Sendable {
    case info = 0       // purely informational (e.g. metadata removed by request)
    case warning = 1    // quality/feature change the user should acknowledge
    case blocking = 2   // conversion cannot proceed with the chosen settings

    public static func < (lhs: ChangeSeverity, rhs: ChangeSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A single predicted difference between source and output.
public struct FeatureChange: Equatable, Sendable {
    public let severity: ChangeSeverity
    /// Short user-facing sentence, English.
    public let message: String
    /// Optional machine-readable reason for grouping/tests.
    public let code: String?

    public init(severity: ChangeSeverity, message: String, code: String? = nil) {
        self.severity = severity
        self.message = message
        self.code = code
    }
}

/// Outcome of planning a single job.
public enum PlanStatus: Equatable, Sendable {
    case ready
    case warning
    case blocked

    public var isConvertible: Bool { self != .blocked }
}

/// A plan for converting one source to the chosen target.
public struct ConversionPlan: Equatable, Sendable {
    public let source: ImageInfo
    public let targetUTI: String
    public let targetDisplayName: String
    public let codecId: String
    public let settings: ConversionSettings
    public let status: PlanStatus
    public let changes: [FeatureChange]
    /// Whether this plan will produce more than one output file.
    public let expandsFramesOrPages: Bool
    /// True when the conversion is not a bit-exact raster conversion
    /// (RAW/PSD/SVG/PDF rasterization).
    public let isStructural: Bool

    public var isConvertible: Bool { status.isConvertible }

    public var blockingChanges: [FeatureChange] { changes.filter { $0.severity == .blocking } }
    public var warnings: [FeatureChange] { changes.filter { $0.severity == .warning } }
    public var infos: [FeatureChange] { changes.filter { $0.severity == .info } }

    /// Human summary line for the main UI.
    public var summary: String {
        switch status {
        case .ready: return "Ready"
        case .warning: return warnings.first?.message ?? "Ready with warnings"
        case .blocked: return blockingChanges.first?.message ?? "Cannot convert"
        }
    }
}
