import Foundation

public struct BessieIntentRequest: Codable, Equatable, Sendable {
    public let v: Int
    public let id: String
    public let intent: BessieIntentID
    public let params: [String: JSONValue]
    public let confirmToken: String?

    public init(
        v: Int = 1,
        id: String,
        intent: BessieIntentID,
        params: [String: JSONValue],
        confirmToken: String? = nil
    ) {
        self.v = v
        self.id = id
        self.intent = intent
        self.params = params
        self.confirmToken = confirmToken
    }

    public init(
        v: Int = 1,
        id: String,
        intent: String,
        params: [String: JSONValue],
        confirmToken: String? = nil
    ) {
        self.init(v: v, id: id, intent: BessieIntentID(intent), params: params, confirmToken: confirmToken)
    }

    enum CodingKeys: String, CodingKey {
        case v, id, intent, params
        case confirmToken = "confirm_token"
    }
}

public enum BessieIntentErrorCode: String, Codable, Equatable, Sendable {
    case bessieNotRunning = "bessie_not_running"
    case unknownIntent = "unknown_intent"
    case invalidParams = "invalid_params"
    case needsConfirmation = "needs_confirmation"
    case confirmTokenInvalid = "confirm_token_invalid"
    case herdrError = "herdr_error"
    case notConnected = "not_connected"
    case unsupported
}

public struct BessieIntentError: Codable, Equatable, Sendable {
    public let code: BessieIntentErrorCode
    public let message: String
    public let confirmToken: String?

    public init(code: BessieIntentErrorCode, message: String, confirmToken: String? = nil) {
        self.code = code
        self.message = message
        self.confirmToken = confirmToken
    }

    enum CodingKeys: String, CodingKey {
        case code, message
        case confirmToken = "confirm_token"
    }
}

public struct BessieIntentResult: Codable, Equatable, Sendable {
    public let v: Int
    public let id: String
    public let ok: Bool
    public let value: JSONValue?
    public let error: BessieIntentError?

    public static func success(id: String, value: JSONValue) -> BessieIntentResult {
        BessieIntentResult(v: 1, id: id, ok: true, value: value, error: nil)
    }

    public static func failure(
        id: String,
        code: BessieIntentErrorCode,
        message: String,
        confirmToken: String? = nil
    ) -> BessieIntentResult {
        BessieIntentResult(
            v: 1,
            id: id,
            ok: false,
            value: nil,
            error: BessieIntentError(code: code, message: message, confirmToken: confirmToken)
        )
    }
}

public struct BessieIntentSessionProjection: Codable, Equatable, Sendable {
    public let connectionID: String
    public let version: String
    public let protocolVersion: Int
    public let focusedWorkspaceID: String?
    public let focusedTabID: String?
    public let focusedPaneID: String?
    public let workspaces: [WorkspaceProjection]
    public let tabs: [TabProjection]
    public let panes: [PaneProjection]
    public let agents: [AgentProjection]
    public let layouts: [JSONValue]

    public init(connectionID: String, projection: HerdrSessionProjection) {
        self.connectionID = connectionID
        version = projection.snapshot.version
        protocolVersion = projection.snapshot.protocolVersion
        focusedWorkspaceID = projection.snapshot.focusedWorkspaceID
        focusedTabID = projection.snapshot.focusedTabID
        focusedPaneID = projection.snapshot.focusedPaneID
        workspaces = projection.workspaces
        tabs = projection.tabs
        panes = projection.panes
        agents = projection.agents
        layouts = projection.snapshot.layouts
    }

    enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case version
        case protocolVersion = "protocol"
        case focusedWorkspaceID = "focused_workspace_id"
        case focusedTabID = "focused_tab_id"
        case focusedPaneID = "focused_pane_id"
        case workspaces, tabs, panes, agents, layouts
    }
}

public protocol BessieIntentLivePort: Sendable {
    func isConnected(connectionID: String?) -> Bool
    func projection(connectionID: String) throws -> HerdrSessionProjection
    func perform(_ action: HerdrAction, connectionID: String) throws -> HerdrSessionProjection
}

public protocol BessieIntentProjectReadPort: Sendable {
    func listProjects() throws -> [BessieProject]
    func project(id: UUID) throws -> BessieProject?
}

extension BessieProjectStore: BessieIntentProjectReadPort {
    public func listProjects() throws -> [BessieProject] { try list().projects.map(\.project) }

    public func project(id: UUID) throws -> BessieProject? {
        do { return try load(id: id).project }
        catch BessieProjectStoreError.notFound { return nil }
    }
}

public struct BessieIntentExecutor: Sendable {
    private let live: any BessieIntentLivePort
    private let projects: any BessieIntentProjectReadPort
    private let confirmations: ConfirmationStore

    public init(
        live: any BessieIntentLivePort,
        projects: any BessieIntentProjectReadPort,
        tokenSource: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.live = live
        self.projects = projects
        confirmations = ConfirmationStore(tokenSource: tokenSource)
    }

    public func execute(_ request: BessieIntentRequest) -> BessieIntentResult {
        guard request.v == 1 else {
            return .failure(id: request.id, code: .unsupported, message: "Unsupported intent protocol version \(request.v).")
        }
        guard let definition = BessieIntentRegistry.definition(for: request.intent) else {
            return .failure(id: request.id, code: .unknownIntent, message: "Unknown intent '\(request.intent.rawValue)'.")
        }
        if let message = validate(request.params, against: definition.paramsSchema) {
            return .failure(id: request.id, code: .invalidParams, message: message)
        }

        let connectionID = request.params.string("connection_id")
        if definition.requiresLiveConnection, !live.isConnected(connectionID: connectionID) {
            return .failure(id: request.id, code: .notConnected, message: "Herdr connection '\(connectionID ?? "")' is not connected.")
        }

        do {
            return try route(request, connectionID: connectionID)
        } catch {
            return .failure(id: request.id, code: .herdrError, message: error.localizedDescription)
        }
    }

    private func route(_ request: BessieIntentRequest, connectionID: String?) throws -> BessieIntentResult {
        switch request.intent.rawValue {
        case "intents.list":
            let catalog = BessieIntentCatalog(
                version: BessieIntentRegistry.catalog.version,
                intents: BessieIntentRegistry.catalog.intents.filter {
                    !$0.requiresLiveConnection || live.isConnected(connectionID: nil)
                }
            )
            return try success(request, catalog)
        case "app.status":
            return .success(id: request.id, value: .object(["running": .bool(true), "bus_version": .number(1)]))
        case "connection.status":
            return .success(id: request.id, value: .object([
                "connected": .bool(live.isConnected(connectionID: connectionID)),
                "connection_id": connectionID.map(JSONValue.string) ?? .null,
            ]))
        case "session.projection":
            let connectionID = required(connectionID)
            return try success(
                request,
                BessieIntentSessionProjection(
                    connectionID: connectionID,
                    projection: live.projection(connectionID: connectionID)
                )
            )
        case "pane.focus":
            return try perform(.paneFocus(id: required(request.params.string("pane_id"))), request: request, connectionID: required(connectionID))
        case "workspace.focus":
            return try perform(.workspaceFocus(id: required(request.params.string("workspace_id"))), request: request, connectionID: required(connectionID))
        case "workspace.close":
            return try closeWorkspace(request, connectionID: required(connectionID))
        case "project.list":
            return try success(request, projects.listProjects())
        case "project.show":
            guard let id = UUID(uuidString: required(request.params.string("project_id"))) else {
                return .failure(id: request.id, code: .invalidParams, message: "Parameter 'project_id' must be a UUID string.")
            }
            guard let project = try projects.project(id: id) else {
                return .failure(id: request.id, code: .unsupported, message: "Project '\(id.uuidString)' was not found.")
            }
            return try success(request, project)
        default:
            return .failure(id: request.id, code: .unknownIntent, message: "Unknown intent '\(request.intent.rawValue)'.")
        }
    }

    private func closeWorkspace(_ request: BessieIntentRequest, connectionID: String) throws -> BessieIntentResult {
        let workspaceID = required(request.params.string("workspace_id"))
        let binding = try canonicalBinding(for: request)
        if let token = request.confirmToken {
            guard confirmations.consume(token: token, binding: binding) else {
                return .failure(id: request.id, code: .confirmTokenInvalid, message: "Confirmation token is invalid, used, or does not match this request.")
            }
            return try perform(.workspaceClose(id: workspaceID), request: request, connectionID: connectionID)
        }

        let projection = try live.projection(connectionID: connectionID)
        let message = projection.confirmationForClosingWorkspace(id: workspaceID).message
        let token = confirmations.issue(binding: binding)
        return .failure(id: request.id, code: .needsConfirmation, message: message, confirmToken: token)
    }

    private func perform(_ action: HerdrAction, request: BessieIntentRequest, connectionID: String) throws -> BessieIntentResult {
        try success(
            request,
            BessieIntentSessionProjection(
                connectionID: connectionID,
                projection: live.perform(action, connectionID: connectionID)
            )
        )
    }

    private func success<T: Encodable>(_ request: BessieIntentRequest, _ value: T) throws -> BessieIntentResult {
        .success(id: request.id, value: try JSONValue(encoded: value))
    }

    private func canonicalBinding(for request: BessieIntentRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(JSONValue.object([
            "intent": .string(request.intent.rawValue),
            "params": .object(request.params),
        ]))
    }

    private func required<T>(_ value: T?) -> T { value! }
}

private final class ConfirmationStore: @unchecked Sendable {
    private let lock = NSLock()
    private let tokenSource: @Sendable () -> String
    private var bindings: [String: Data] = [:]

    init(tokenSource: @escaping @Sendable () -> String) { self.tokenSource = tokenSource }

    func issue(binding: Data) -> String {
        lock.withLock {
            var token = tokenSource()
            while bindings[token] != nil { token = tokenSource() }
            bindings[token] = binding
            return token
        }
    }

    func consume(token: String, binding: Data) -> Bool {
        lock.withLock {
            guard bindings[token] == binding else { return false }
            bindings.removeValue(forKey: token)
            return true
        }
    }
}

private func validate(_ params: [String: JSONValue], against schema: BessieJSONSchema) -> String? {
    let properties = schema.properties ?? [:]
    if let unknown = params.keys.first(where: { properties[$0] == nil }) {
        return "Unknown parameter '\(unknown)'."
    }
    if let missing = (schema.required ?? []).first(where: { params[$0] == nil }) {
        return "Missing required parameter '\(missing)'."
    }
    for (name, value) in params {
        guard value.matches(properties[name]?.type) else { return "Parameter '\(name)' has the wrong type." }
    }
    return nil
}

private extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? {
        guard case .string(let value) = self[key] else { return nil }
        return value
    }
}

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }
}

private extension JSONValue {
    init<T: Encodable>(encoded value: T) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    func matches(_ type: BessieJSONSchemaType?) -> Bool {
        switch (self, type) {
        case (.object, .object), (.string, .string), (.number, .number), (.number, .integer), (.bool, .boolean), (.array, .array): true
        default: false
        }
    }

}
