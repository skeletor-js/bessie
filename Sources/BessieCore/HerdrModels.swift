import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    func decode<T: Decodable>(_ type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
}

public struct HerdrSnapshot: Codable, Equatable, Sendable {
    public let version: String
    public let protocolVersion: Int
    public let focusedWorkspaceID: String?
    public let focusedTabID: String?
    public let focusedPaneID: String?
    public let workspaces: [JSONValue]
    public let tabs: [JSONValue]
    public let panes: [JSONValue]
    public let layouts: [JSONValue]
    public let agents: [JSONValue]

    public init(
        version: String,
        protocolVersion: Int,
        focusedWorkspaceID: String?,
        focusedTabID: String?,
        focusedPaneID: String?,
        workspaces: [JSONValue],
        tabs: [JSONValue],
        panes: [JSONValue],
        layouts: [JSONValue],
        agents: [JSONValue]
    ) {
        self.version = version
        self.protocolVersion = protocolVersion
        self.focusedWorkspaceID = focusedWorkspaceID
        self.focusedTabID = focusedTabID
        self.focusedPaneID = focusedPaneID
        self.workspaces = workspaces
        self.tabs = tabs
        self.panes = panes
        self.layouts = layouts
        self.agents = agents
    }

    enum CodingKeys: String, CodingKey {
        case version
        case protocolVersion = "protocol"
        case focusedWorkspaceID = "focused_workspace_id"
        case focusedTabID = "focused_tab_id"
        case focusedPaneID = "focused_pane_id"
        case workspaces, tabs, panes, layouts, agents
    }
}

public struct HerdrEvent: Codable, Equatable, Sendable {
    public let name: String
    public let data: [String: JSONValue]

    public init(name: String, data: [String: JSONValue]) {
        self.name = name
        self.data = data
    }

    enum CodingKeys: String, CodingKey { case name = "event", data }
}

public struct HerdrServerIdentity: Codable, Equatable, Sendable {
    public let version: String
    public let protocolVersion: Int

    public init(version: String, protocolVersion: Int) {
        self.version = version
        self.protocolVersion = protocolVersion
    }
}

public enum HerdrClientError: Error, Equatable, LocalizedError, Sendable {
    case invalidNDJSON(String)
    case mismatchedResponseID(expected: String, actual: String)
    case server(code: String, message: String)
    case unexpectedResponse(String)
    case socket(path: String, message: String)
    case connectionClosed
    case process(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidNDJSON(let message): return "Bessie received invalid data from Herdr. \(message)"
        case .mismatchedResponseID: return "Bessie received an out-of-order response from Herdr."
        case .server(_, let message): return message
        case .unexpectedResponse(let message): return "Herdr returned an unexpected response. \(message)"
        case .socket(_, let message): return "Couldn't connect to Herdr. \(message)"
        case .connectionClosed: return "Herdr closed the connection."
        case .process(_, let message): return "Couldn't run Herdr. \(message)"
        }
    }
}
