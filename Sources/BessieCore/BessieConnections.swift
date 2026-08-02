import Foundation

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

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: BessieConnectionKind,
        sshHost: String? = nil,
        session: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.sshHost = sshHost?.trimmedOrNil
        self.session = session?.trimmedOrNil
    }

    public static let localBessie = BessieConnectionDefinition(
        id: "local-bessie",
        name: "This Mac",
        kind: .local,
        session: BessieCompatibility.sessionName
    )

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
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._@%+:-]+$"#, options: .regularExpression) != nil
    }

    public static func isSafeSession(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, session
        case sshHost = "ssh_host"
    }
}

public struct BessieConnectionState: Codable, Equatable, Sendable {
    public var selectedConnectionID: String
    public var connections: [BessieConnectionDefinition]

    public init(
        selectedConnectionID: String = BessieConnectionDefinition.localBessie.id,
        connections: [BessieConnectionDefinition] = [.localBessie]
    ) {
        var seen: Set<String> = [BessieConnectionDefinition.localBessie.id]
        var normalized: [BessieConnectionDefinition] = [.localBessie]
        for connection in connections where connection.id != BessieConnectionDefinition.localBessie.id {
            if seen.insert(connection.id).inserted { normalized.append(connection) }
        }
        self.connections = normalized
        self.selectedConnectionID = normalized.contains(where: { $0.id == selectedConnectionID })
            ? selectedConnectionID
            : BessieConnectionDefinition.localBessie.id
    }

    private enum CodingKeys: String, CodingKey {
        case selectedConnectionID = "selected_connection_id"
        case connections
    }
}

public struct BessieConnectionStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> BessieConnectionState {
        guard FileManager.default.fileExists(atPath: url.path) else { return BessieConnectionState() }
        let decoded = try JSONDecoder().decode(BessieConnectionState.self, from: Data(contentsOf: url))
        return BessieConnectionState(
            selectedConnectionID: decoded.selectedConnectionID,
            connections: decoded.connections
        )
    }

    public func save(_ state: BessieConnectionState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
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
