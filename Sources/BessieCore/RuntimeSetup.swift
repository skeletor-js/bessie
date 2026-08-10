import Foundation

public enum HerdrRuntimeSelection: Equatable, Sendable {
    case bundled
    case system
    case custom(URL)
}

extension HerdrRuntimeSelection: Codable {
    private enum Keys: String, CodingKey { case version, kind, path }
    private enum Kind: String, Codable { case bundled, system, custom }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        guard try values.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported runtime selection version")
        }
        switch try values.decode(Kind.self, forKey: .kind) {
        case .bundled: self = .bundled
        case .system: self = .system
        case .custom:
            let path = try values.decode(String.self, forKey: .path)
            guard path.hasPrefix("/") else {
                throw DecodingError.dataCorruptedError(forKey: .path, in: values, debugDescription: "Custom runtime path must be absolute")
            }
            self = .custom(URL(fileURLWithPath: path))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(1, forKey: .version)
        switch self {
        case .bundled: try values.encode(Kind.bundled, forKey: .kind)
        case .system: try values.encode(Kind.system, forKey: .kind)
        case .custom(let url):
            try values.encode(Kind.custom, forKey: .kind)
            try values.encode(url.path, forKey: .path)
        }
    }
}

public struct HerdrRuntimeSelectionStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() -> HerdrRuntimeSelection {
        guard let data = try? Data(contentsOf: url) else { return .bundled }
        return (try? JSONDecoder().decode(HerdrRuntimeSelection.self, from: data)) ?? .bundled
    }
    public func save(_ selection: HerdrRuntimeSelection) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(selection).write(to: url, options: .atomic)
    }
}

public enum RuntimeResolutionFailure: Error, Equatable, Sendable {
    case bundledMissing, bundledNotExecutable, systemMissing, customMissing(String), customNotExecutable(String)
}

public struct BundledRuntimeLock: Equatable, Sendable {
    public let canonicalURL: URL
    public let sha256: String
    public let versionOutput: String
    public let protocolVersion: Int

    public init(canonicalURL: URL, sha256: String, versionOutput: String, protocolVersion: Int) {
        self.canonicalURL = canonicalURL.standardizedFileURL
        self.sha256 = sha256.lowercased()
        self.versionOutput = versionOutput
        self.protocolVersion = protocolVersion
    }
}

public struct ValidatedRuntime: Equatable, Sendable {
    public let runtime: HerdrRuntime
    public let version: String
    public let protocolVersion: Int
}

public enum RuntimeValidationFailure: Error, Equatable, Sendable {
    case bundledIntegrity
    case externalMissing(String)
    case externalNotExecutable(String)
    case incompatible(version: String?, protocolVersion: Int?)
    case permission(String)
    case filesystem(String)
}

public struct RuntimeFileFacts: Equatable, Sendable {
    public var exists: Bool
    public var regularFile: Bool
    public var executable: Bool
    public var arm64: Bool
    public var sha256: String?
    public var signatureValid: Bool

    public init(exists: Bool, regularFile: Bool, executable: Bool, arm64: Bool, sha256: String?, signatureValid: Bool) {
        self.exists = exists; self.regularFile = regularFile; self.executable = executable
        self.arm64 = arm64; self.sha256 = sha256; self.signatureValid = signatureValid
    }
}

/// Validates the selected executable before any server status is consulted.
/// File inspection and executable identity are injected so Core has no bundle or signing policy dependency.
public struct HerdrRuntimeValidator: Sendable {
    public typealias FileInspector = @Sendable (URL) throws -> RuntimeFileFacts
    public typealias IdentityProvider = @Sendable (URL) throws -> HerdrServerIdentity
    private let inspect: FileInspector
    private let identity: IdentityProvider

    public init(inspect: @escaping FileInspector, identity: @escaping IdentityProvider) {
        self.inspect = inspect; self.identity = identity
    }

    public func validate(_ runtime: HerdrRuntime, bundledLock: BundledRuntimeLock?) throws -> ValidatedRuntime {
        let facts: RuntimeFileFacts
        do { facts = try inspect(runtime.url) }
        catch let error as CocoaError where error.code == .fileReadNoPermission { throw RuntimeValidationFailure.permission(runtime.url.path) }
        catch { throw RuntimeValidationFailure.filesystem(runtime.url.path) }
        let bundled = runtime.source == .bundled
        guard facts.exists, facts.regularFile else {
            throw bundled
                ? RuntimeValidationFailure.bundledIntegrity
                : RuntimeValidationFailure.externalMissing(runtime.url.path)
        }
        guard facts.executable else {
            throw bundled
                ? RuntimeValidationFailure.bundledIntegrity
                : RuntimeValidationFailure.externalNotExecutable(runtime.url.path)
        }
        guard facts.arm64 else {
            throw bundled
                ? RuntimeValidationFailure.bundledIntegrity
                : RuntimeValidationFailure.incompatible(version: nil, protocolVersion: nil)
        }
        if bundled {
            guard let lock = bundledLock,
                  runtime.url.standardizedFileURL == lock.canonicalURL,
                  facts.sha256?.lowercased() == lock.sha256,
                  facts.signatureValid
            else { throw RuntimeValidationFailure.bundledIntegrity }
        }
        let observed: HerdrServerIdentity
        do { observed = try identity(runtime.url) }
        catch let error as CocoaError where error.code == .fileReadNoPermission { throw RuntimeValidationFailure.permission(runtime.url.path) }
        catch {
            throw bundled
                ? RuntimeValidationFailure.bundledIntegrity
                : RuntimeValidationFailure.incompatible(version: nil, protocolVersion: nil)
        }
        guard observed.version == BessieCompatibility.herdrVersion,
              observed.protocolVersion == BessieCompatibility.protocolVersion,
              !bundled || (bundledLock?.versionOutput == "herdr \(observed.version)" && bundledLock?.protocolVersion == observed.protocolVersion)
        else { throw RuntimeValidationFailure.incompatible(version: observed.version, protocolVersion: observed.protocolVersion) }
        return ValidatedRuntime(runtime: runtime, version: observed.version, protocolVersion: observed.protocolVersion)
    }
}

extension RuntimeResolutionFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bundledMissing, .bundledNotExecutable: "This copy of Bessie is damaged. Its included Herdr runtime is missing or cannot run."
        case .systemMissing: "The selected system Herdr runtime could not be found. Choose another runtime in Settings."
        case .customMissing(let path): "The selected Herdr runtime is missing at \(path)."
        case .customNotExecutable(let path): "The selected Herdr runtime cannot be executed at \(path)."
        }
    }
}

public enum SetupStage: String, Codable, CaseIterable, Sendable {
    case runtimeResolution, runtimeValidation, serverStatus, apiConnection, terminalController, workspaceReady
}

public enum SetupFinding: String, Codable, CaseIterable, Sendable {
    case bundledIntegrity, externalMissing, externalNotExecutable, incompatible, serverStartup, apiUnavailable,
         terminalControlUnavailable, permissionOrFilesystem, previouslyHealthyLoss

    public var safeActions: [SetupAction] {
        switch self {
        case .bundledIntegrity: [.copyReport, .revealRuntime]
        case .externalMissing, .externalNotExecutable, .incompatible: [.openSettings, .copyReport]
        case .serverStartup, .apiUnavailable, .terminalControlUnavailable, .previouslyHealthyLoss: [.retry, .copyReport]
        case .permissionOrFilesystem: [.revealRuntime, .copyReport]
        }
    }
}

public enum SetupAction: String, Codable, CaseIterable, Hashable, Sendable {
    case retry, revealRuntime, copyReport, openSettings
}

public struct TerminalControllerFacts: Equatable, Sendable {
    public var ready: Int
    public var reconnecting: Int
    public var ownershipConflicts: Int
    public var failed: Int

    public init(ready: Int = 0, reconnecting: Int = 0, ownershipConflicts: Int = 0, failed: Int = 0) {
        self.ready = ready
        self.reconnecting = reconnecting
        self.ownershipConflicts = ownershipConflicts
        self.failed = failed
    }

    public var healthy: Bool { ready > 0 && reconnecting == 0 && ownershipConflicts == 0 && failed == 0 }
    public var finding: SetupFinding? { ownershipConflicts > 0 || failed > 0 ? .terminalControlUnavailable : nil }
}

public struct RuntimeDiagnosticSnapshot: Equatable, Sendable {
    public var stage: SetupStage
    public var finding: SetupFinding?
    public var runtime: HerdrRuntime?
    public var observedVersion: String?
    public var observedProtocol: Int?
    public var session: String
    public var apiSocketPath: String?
    public var apiHealthy: Bool
    public var terminalControllerHealthy: Bool

    public init(stage: SetupStage, finding: SetupFinding? = nil, runtime: HerdrRuntime? = nil,
                observedVersion: String? = nil, observedProtocol: Int? = nil,
                session: String = BessieCompatibility.sessionName, apiSocketPath: String? = nil,
                apiHealthy: Bool = false, terminalControllerHealthy: Bool = false) {
        self.stage = stage; self.finding = finding; self.runtime = runtime
        self.observedVersion = observedVersion; self.observedProtocol = observedProtocol; self.session = session
        self.apiSocketPath = apiSocketPath; self.apiHealthy = apiHealthy
        self.terminalControllerHealthy = terminalControllerHealthy
    }

    public var sanitizedReport: String {
        ["Bessie Setup Doctor", "stage=\(stage.rawValue)", "finding=\(finding?.rawValue ?? "none")",
         "source=\(runtime?.source.rawValue ?? "unresolved")", "runtime_location=\(runtime?.source == .bundled ? "bundled" : runtime == nil ? "unresolved" : "external")",
         "expected_version=\(BessieCompatibility.herdrVersion)", "observed_version=\(observedVersion ?? "unknown")",
         "expected_protocol=\(BessieCompatibility.protocolVersion)", "observed_protocol=\(observedProtocol.map(String.init) ?? "unknown")",
         "session_configured=\(!session.isEmpty)", "socket_configured=\(apiSocketPath?.isEmpty == false)", "api_healthy=\(apiHealthy)",
         "terminal_controller_healthy=\(terminalControllerHealthy)"].joined(separator: "\n")
    }

    public var availableActions: [SetupAction] { finding?.safeActions ?? [] }

    public func runtimeRevealURL(fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> URL? {
        guard let runtime else { return nil }
        var candidate = runtime.url.standardizedFileURL
        if runtime.source == .bundled {
            while candidate.path != "/" {
                if candidate.pathExtension == "app" { return candidate }
                candidate.deleteLastPathComponent()
            }
            candidate = runtime.url.standardizedFileURL
        }
        while candidate.path != "/", !fileExists(candidate.path) {
            candidate.deleteLastPathComponent()
        }
        return fileExists(candidate.path) ? candidate : nil
    }
}

public struct OnboardingState: Codable, Equatable, Sendable {
    public enum Step: Int, Codable, CaseIterable, Sendable { case connect = 1, howItWorks, readTheRail, notifications }
    public var step: Step
    public var completed: Bool
    public init(step: Step = .connect, completed: Bool = false) { self.step = step; self.completed = completed }
    public mutating func advance(runtimeReady: Bool, sessionReady: Bool, workspaceReady: Bool, terminalControllerReady: Bool) {
        switch step {
        case .connect: if runtimeReady && sessionReady { step = .howItWorks }
        case .howItWorks: step = .readTheRail
        case .readTheRail: step = .notifications
        case .notifications: if terminalControllerReady { completed = true }
        }
    }
    public mutating func goBack() {
        guard !completed, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
    public mutating func runAgain() { step = .connect; completed = false }
}

public enum OnboardingCompletionStage: String, Codable, CaseIterable, Sendable {
    case idle, validating, startingSession, connecting, creatingWorkspace, adoptingWorkspace, waitingForFirstFrame, completed, failed

    public var hasMaterialized: Bool {
        switch self {
        case .startingSession, .connecting, .creatingWorkspace, .adoptingWorkspace, .waitingForFirstFrame, .completed, .failed: true
        case .idle, .validating: false
        }
    }
}

public struct PendingOnboardingAttempt: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public let schemaVersion: Int
    public let attemptID: String
    public var connectionID: String
    public let sessionName: String
    public let path: String
    public var stage: OnboardingCompletionStage
    public var workspaceID: String?
    public var tabID: String?
    public var paneID: String?

    public init(attemptID: String = "bessie-\(UUID().uuidString.lowercased())", connectionID: String,
                sessionName: String = "bessie-onboarding-\(UUID().uuidString.lowercased())", path: String,
                stage: OnboardingCompletionStage = .idle, workspaceID: String? = nil,
                tabID: String? = nil, paneID: String? = nil, schemaVersion: Int = Self.schemaVersion) throws {
        guard schemaVersion == Self.schemaVersion else { throw OnboardingPersistenceError.unsupportedSchema(schemaVersion) }
        guard BessieConnectionDefinition.isSafeSession(attemptID), BessieConnectionDefinition.isSafeSession(sessionName) else {
            throw OnboardingPersistenceError.invalidIdentifier
        }
        self.schemaVersion = schemaVersion; self.attemptID = attemptID; self.connectionID = connectionID
        self.sessionName = sessionName; self.path = try OnboardingPathValidator.absolute(path)
        self.stage = stage; self.workspaceID = workspaceID; self.tabID = tabID; self.paneID = paneID
    }
}

public enum OnboardingPersistenceError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int), invalidIdentifier, pathMustBeAbsolute
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): "This setup attempt uses unsupported schema version \(version). Update Bessie before retrying."
        case .invalidIdentifier: "The setup attempt identifier is invalid. Start setup again."
        case .pathMustBeAbsolute: "Choose an absolute folder path."
        }
    }
}

public enum OnboardingPathValidator {
    public static func absolute(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), !trimmed.contains("\0") else { throw OnboardingPersistenceError.pathMustBeAbsolute }
        return URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
    }

    public static func localPathsAreEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        canonicalLocalURL(lhs) == canonicalLocalURL(rhs)
    }

    private static func canonicalLocalURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
}

public struct PendingOnboardingAttemptStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> PendingOnboardingAttempt? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        guard probe.schemaVersion == PendingOnboardingAttempt.schemaVersion else {
            throw OnboardingPersistenceError.unsupportedSchema(probe.schemaVersion)
        }
        return try JSONDecoder().decode(PendingOnboardingAttempt.self, from: data)
    }
    public func save(_ attempt: PendingOnboardingAttempt) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(attempt).write(to: url, options: .atomic)
    }
    public func clear() throws { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
    private struct SchemaProbe: Decodable { let schemaVersion: Int }
}
