import Foundation

public struct ConnectionDisplayLabel: Equatable, Sendable {
    private static let genericSSHNames = Set(["connection", "remote", "ssh"])

    public let short: String
    public let detail: String
    public let kind: BessieConnectionKind

    public init(connection: BessieConnectionDefinition) {
        let name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if connection.kind == .ssh,
           (name.isEmpty || Self.genericSSHNames.contains(name.lowercased())),
           let sshHost = connection.sshHost {
            short = sshHost
        } else {
            short = name.isEmpty ? (connection.sshHost ?? "Connection") : name
        }
        detail = connection.detail
        kind = connection.kind
    }
}
