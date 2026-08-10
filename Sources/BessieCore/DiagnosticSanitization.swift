import Foundation

public enum DiagnosticErrorClass: String, Codable, CaseIterable, Sendable {
    case runtimeMissing = "runtime_missing"
    case runtimeIncompatible = "runtime_incompatible"
    case permissionOrFilesystem = "permission_or_filesystem"
    case apiUnavailable = "api_unavailable"
    case controllerConflict = "controller_conflict"
    case controllerDisconnected = "controller_disconnected"
    case connectionLost = "connection_lost"
    case corruptedPersistence = "corrupted_persistence"
    case unsupportedSchema = "unsupported_schema"
    case unknown
}

public enum DiagnosticFact: Equatable, Sendable {
    case apiHealthy(Bool)
    case controllerHealthy(Bool)
    case retryAttempt(Int)
    case protocolVersion(Int)

    fileprivate var reportLine: String {
        switch self {
        case .apiHealthy(let value): "api_healthy=\(value)"
        case .controllerHealthy(let value): "controller_healthy=\(value)"
        case .retryAttempt(let value): "retry_attempt=\(max(0, value))"
        case .protocolVersion(let value): "protocol_version=\(max(0, value))"
        }
    }
}

/// The support boundary deliberately discards arbitrary details. Useful stage/class facts stay typed.
public struct DiagnosticSupportEvidence: Equatable, Sendable {
    public let stage: SetupStage
    public let errorClass: DiagnosticErrorClass
    public let facts: [DiagnosticFact]

    public init(
        stage: SetupStage,
        errorClass: DiagnosticErrorClass,
        untrustedDetail _: String,
        facts: [DiagnosticFact] = []
    ) {
        self.stage = stage
        self.errorClass = errorClass
        self.facts = facts
    }

    public var report: String {
        (["Bessie Diagnostic Evidence", "stage=\(stage.rawValue)", "error_class=\(errorClass.rawValue)"]
            + facts.map(\.reportLine)).joined(separator: "\n")
    }
}

public enum DiagnosticSanitizer {
    /// Do not regex-scrub unknown text: terminal output and novel secret formats are not safely enumerable.
    public static func discardUntrustedText(_ text: String) -> String {
        text.isEmpty ? "[no detail]" : "[redacted untrusted detail]"
    }
}
