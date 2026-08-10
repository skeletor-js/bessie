import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum BessieConnectionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case local
    case ssh
}

public struct BessieConnectionDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var kind: BessieConnectionKind
    public var sshHost: String?
    public var session: String?
    /// Whether Bessie may use this configured herd. Disabled definitions remain saved for recovery.
    public var enabled: Bool
    /// When true, Bessie starts this herd during app launch. Other herds connect on demand.
    public var connectAtLaunch: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: BessieConnectionKind,
        sshHost: String? = nil,
        session: String? = nil,
        enabled: Bool = true,
        connectAtLaunch: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sshHost = sshHost?.trimmedOrNil
        self.session = session?.trimmedOrNil
        self.enabled = enabled
        self.connectAtLaunch = connectAtLaunch ?? Self.defaultConnectAtLaunch(for: kind)
    }

    public static let localBessie = BessieConnectionDefinition(
        id: "local-bessie",
        name: "This Mac",
        kind: .local,
        session: BessieCompatibility.sessionName,
        enabled: true,
        connectAtLaunch: true
    )

    public static func defaultConnectAtLaunch(for kind: BessieConnectionKind) -> Bool {
        switch kind {
        case .local: true
        case .ssh: false
        }
    }

    public var detail: String {
        switch kind {
        case .local:
            return "Local · \(session ?? "default")"
        case .ssh:
            return "SSH · \(sshHost ?? "Missing host") · \(session ?? "default")"
        }
    }

    public func validated() throws -> BessieConnectionDefinition {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BessieConnectionError.invalidName
        }
        if let session, !Self.isSafeSession(session) {
            throw BessieConnectionError.invalidSession
        }
        if kind == .ssh {
            guard let sshHost, Self.isSafeSSHHost(sshHost) else {
                throw BessieConnectionError.invalidSSHHost
            }
        }
        return self
    }

    public static func isSafeSSHHost(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("-")
            && value.range(of: #"^[A-Za-z0-9._@%+:-]+$"#, options: .regularExpression) != nil
    }

    public static func isSafeSession(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, session
        case sshHost = "ssh_host"
        case enabled
        case connectAtLaunch = "connect_at_launch"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(BessieConnectionKind.self, forKey: .kind)
        sshHost = try values.decodeIfPresent(String.self, forKey: .sshHost)?.trimmedOrNil
        session = try values.decodeIfPresent(String.self, forKey: .session)?.trimmedOrNil
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        connectAtLaunch = try values.decodeIfPresent(Bool.self, forKey: .connectAtLaunch)
            ?? Self.defaultConnectAtLaunch(for: kind)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(sshHost, forKey: .sshHost)
        try values.encodeIfPresent(session, forKey: .session)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(connectAtLaunch, forKey: .connectAtLaunch)
    }
}

public struct BessieConnectionState: Codable, Equatable, Sendable {
    public var selectedConnectionID: String
    public var defaultProjectConnectionID: String
    public var connections: [BessieConnectionDefinition]

    public init(
        selectedConnectionID: String = BessieConnectionDefinition.localBessie.id,
        defaultProjectConnectionID: String? = nil,
        connections: [BessieConnectionDefinition] = [.localBessie]
    ) {
        do {
            self = try Self.validated(
                selectedConnectionID: selectedConnectionID,
                defaultProjectConnectionID: defaultProjectConnectionID,
                connections: connections
            )
        } catch {
            preconditionFailure("BessieConnectionState requires at least one enabled connection. Use validated(...) for recoverable input.")
        }
    }

    public static func validated(
        selectedConnectionID: String,
        defaultProjectConnectionID: String? = nil,
        connections: [BessieConnectionDefinition]
    ) throws -> BessieConnectionState {
        var seen: Set<String> = [BessieConnectionDefinition.localBessie.id]
        var local = BessieConnectionDefinition.localBessie
        if let existingLocal = connections.first(where: {
            $0.id == BessieConnectionDefinition.localBessie.id && $0.kind == .local
        }) {
            // Preserve availability and launch preference for the canonical local herd.
            local.enabled = existingLocal.enabled
            local.connectAtLaunch = existingLocal.connectAtLaunch
        }
        var normalized: [BessieConnectionDefinition] = [local]
        for connection in connections where connection.id != BessieConnectionDefinition.localBessie.id {
            if seen.insert(connection.id).inserted { normalized.append(connection) }
        }
        let enabledConnections = normalized.filter(\.enabled)
        guard let fallback = enabledConnections.first else {
            throw BessieConnectionStateError.finalEnabledConnectionRequired
        }
        let enabledIDs = Set(enabledConnections.map(\.id))
        let selected = enabledIDs.contains(selectedConnectionID) ? selectedConnectionID : fallback.id
        let requestedDefault = defaultProjectConnectionID ?? selected
        let defaultProject = enabledIDs.contains(requestedDefault) ? requestedDefault : selected
        return Self(
            selectedConnectionID: selected,
            defaultProjectConnectionID: defaultProject,
            connections: normalized,
            normalized: ()
        )
    }

    private init(
        selectedConnectionID: String,
        defaultProjectConnectionID: String,
        connections: [BessieConnectionDefinition],
        normalized _: Void
    ) {
        self.selectedConnectionID = selectedConnectionID
        self.defaultProjectConnectionID = defaultProjectConnectionID
        self.connections = connections
    }

    private enum CodingKeys: String, CodingKey {
        case selectedConnectionID = "selected_connection_id"
        case defaultProjectConnectionID = "default_project_connection_id"
        case connections
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let selected = try values.decode(String.self, forKey: .selectedConnectionID)
        let defaultProject = try values.decodeIfPresent(String.self, forKey: .defaultProjectConnectionID)
        let connections = try values.decode([BessieConnectionDefinition].self, forKey: .connections)
        self = try Self.validated(
            selectedConnectionID: selected,
            defaultProjectConnectionID: defaultProject,
            connections: connections
        )
    }
}

public enum BessieConnectionStateError: LocalizedError, Equatable, Sendable {
    case finalEnabledConnectionRequired

    public var errorDescription: String? {
        switch self {
        case .finalEnabledConnectionRequired:
            "Keep at least one herd enabled and selected. Enable or add another herd first."
        }
    }
}

public enum BessieConfigurationLeaseError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case migrationInProgress(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let path):
            "Bessie configuration is in use by another process: \(path)"
        case .migrationInProgress(let path):
            "A Bessie data migration is in progress. Keep Bessie closed until it finishes: \(path)"
        }
    }
}

/// Coordinates Bessie's process-lifetime configuration access with the repository migration operator.
/// The app holds a shared lease; a stopped-app migration requires the exclusive lease.
public final class BessieConfigurationLease: @unchecked Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    public static func lockURL(for connectionsURL: URL) -> URL {
        connectionsURL.deletingLastPathComponent().appendingPathComponent(".bessie-configuration.lock")
    }

    public static func activeMigrationMarkerURL(for connectionsURL: URL) -> URL {
        connectionsURL.deletingLastPathComponent().appendingPathComponent(".bessie-migration-active.json")
    }

    public static func acquireShared(for connectionsURL: URL) throws -> BessieConfigurationLease {
        let lease = try acquire(for: connectionsURL, operation: LOCK_SH)
        let marker = activeMigrationMarkerURL(for: connectionsURL)
        var markerDetails = stat()
        if lstat(marker.path, &markerDetails) == 0 {
            throw BessieConfigurationLeaseError.migrationInProgress(marker.path)
        }
        guard errno == ENOENT else {
            throw BessieConfigurationLeaseError.unavailable(marker.path)
        }
        return lease
    }

    public static func acquireExclusive(
        for connectionsURL: URL,
        nonblocking: Bool = true
    ) throws -> BessieConfigurationLease {
        try acquire(for: connectionsURL, operation: LOCK_EX | (nonblocking ? LOCK_NB : 0))
    }

    private static func acquire(for connectionsURL: URL, operation: Int32) throws -> BessieConfigurationLease {
        let lockURL = lockURL(for: connectionsURL)
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let parentURL = lockURL.deletingLastPathComponent()
        var parentDetails = stat()
        guard lstat(parentURL.path, &parentDetails) == 0,
              (parentDetails.st_mode & S_IFMT) == S_IFDIR,
              parentDetails.st_uid == geteuid(),
              (parentDetails.st_mode & 0o022) == 0,
              parentURL.standardizedFileURL.path == parentURL.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw BessieConfigurationLeaseError.unavailable(lockURL.path)
        }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw BessieConfigurationLeaseError.unavailable(lockURL.path)
        }
        var details = stat()
        guard fstat(descriptor, &details) == 0, (details.st_mode & S_IFMT) == S_IFREG,
              details.st_uid == geteuid(), details.st_nlink == 1,
              (details.st_mode & 0o077) == 0,
              flock(descriptor, operation) == 0 else {
            close(descriptor)
            throw BessieConfigurationLeaseError.unavailable(lockURL.path)
        }
        return BessieConfigurationLease(descriptor: descriptor)
    }
}

/// Chooses which configured herds Bessie should start during app launch.
public enum BessieLaunchConnections: Sendable {
    /// Enabled herds explicitly configured to connect when Bessie launches.
    /// On-demand herds remain stopped until the user selects them or launches a Project against them.
    public static func startupConnections(
        connections: [BessieConnectionDefinition],
        selectedConnectionID: String
    ) -> [BessieConnectionDefinition] {
        connections.filter { $0.enabled && $0.connectAtLaunch }
    }

    public static func preferredActiveConnectionID(
        startupConnections: [BessieConnectionDefinition],
        selectedConnectionID: String
    ) -> String? {
        if startupConnections.contains(where: { $0.id == selectedConnectionID }) {
            return selectedConnectionID
        }
        return startupConnections.first?.id
    }
}

public struct BessieConnectionStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> BessieConnectionState {
        guard FileManager.default.fileExists(atPath: url.path) else { return BessieConnectionState() }
        return try JSONDecoder().decode(BessieConnectionState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: BessieConnectionState) throws {
        let validated = try BessieConnectionState.validated(
            selectedConnectionID: state.selectedConnectionID,
            defaultProjectConnectionID: state.defaultProjectConnectionID,
            connections: state.connections
        )
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(validated).write(to: url, options: .atomic)
    }
}

public enum BessieConnectionError: LocalizedError, Equatable, Sendable {
    case invalidName
    case invalidSSHHost
    case invalidSession
    case sshFailed(String)
    case remoteHerdrUnavailable(String)
    case tunnelFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Give the connection a name."
        case .invalidSSHHost: "Use an SSH config host or user@host without spaces or shell characters."
        case .invalidSession: "Herdr session names may contain letters, numbers, dots, underscores, and hyphens."
        case .sshFailed(let reason): "SSH connection failed. \(reason)"
        case .remoteHerdrUnavailable(let reason): "Remote Herdr is unavailable. \(reason)"
        case .tunnelFailed(let reason): "Couldn't open the private Herdr tunnel. \(reason)"
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
