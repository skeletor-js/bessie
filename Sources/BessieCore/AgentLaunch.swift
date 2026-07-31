import Foundation

public protocol AgentAvailabilityChecking: Sendable {
    func executablePath(for kind: String) -> String?
}

public struct PATHAgentAvailabilityChecker: AgentAvailabilityChecking, Sendable {
    private let searchPaths: [String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        searchPaths = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    public func executablePath(for kind: String) -> String? {
        for directory in searchPaths {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(kind).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

private struct AgentManifestInfo: Codable, Equatable, Sendable {
    public let agent: String
    public let activeVersion: String?

    enum CodingKeys: String, CodingKey {
        case agent
        case activeVersion = "active_version"
    }
}

public enum AgentAvailability: Equatable, Sendable {
    case available(executablePath: String)
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public struct AgentCatalogItem: Identifiable, Equatable, Sendable {
    public var id: String { kind }
    public let kind: String
    public let displayName: String
    public let version: String?
    public let availability: AgentAvailability
}

public struct AgentCatalog: Equatable, Sendable {
    public let items: [AgentCatalogItem]

    public init(items: [AgentCatalogItem]) { self.items = items }

    public init(serverResult: JSONValue, availability: any AgentAvailabilityChecking) throws {
        guard case .object(let object) = serverResult,
              object["type"] == .string("agent_manifest_status"),
              case .array(let values) = object["manifests"]
        else { throw HerdrClientError.unexpectedResponse("server.agent_manifests did not return agent_manifest_status") }
        items = try values.map { value in
            let manifest = try value.decode(AgentManifestInfo.self)
            let state: AgentAvailability
            if let path = availability.executablePath(for: manifest.agent) {
                state = .available(executablePath: path)
            } else {
                state = .unavailable(reason: "\(manifest.agent) is not installed or is not on PATH")
            }
            return AgentCatalogItem(
                kind: manifest.agent,
                displayName: Self.displayName(manifest.agent),
                version: manifest.activeVersion,
                availability: state
            )
        }.sorted { $0.kind < $1.kind }
    }

    public static func load(api: HerdrSocketAPI, availability: any AgentAvailabilityChecking = PATHAgentAvailabilityChecker()) throws -> AgentCatalog {
        try AgentCatalog(serverResult: api.request(method: "server.agent_manifests"), availability: availability)
    }

    private static func displayName(_ kind: String) -> String {
        switch kind {
        case "codex": "Codex"
        case "claude": "Claude"
        case "gemini": "Gemini"
        case "opencode": "OpenCode"
        case "copilot": "Copilot"
        default: kind.prefix(1).uppercased() + kind.dropFirst()
        }
    }
}

public enum AgentSemanticName {
    public static func unique(kind: String, existing: Set<String>) -> String {
        if !existing.contains(kind) { return kind }
        var suffix = 2
        while existing.contains("\(kind)-\(suffix)") { suffix += 1 }
        return "\(kind)-\(suffix)"
    }
}

public enum NewProcessPlacement: Equatable, Sendable {
    case split(targetPaneID: String, direction: SplitDirection, cwd: String?)
    case newTab(workspaceID: String, cwd: String?)
}

public enum NewProcessChoice: Equatable, Sendable {
    case shell
    case agent(kind: String, name: String, args: [String], timeoutMilliseconds: UInt64?)
}

public struct ProcessLaunchResult: Equatable, Sendable {
    public let projection: HerdrSessionProjection
    public let paneID: String
    public let agentStarted: Bool
    public let agentError: String?
}

public struct HerdrProcessLauncher: Sendable {
    private let api: any HerdrMutationAPI
    public init(api: any HerdrMutationAPI) { self.api = api }

    public func launch(placement: NewProcessPlacement, process: NewProcessChoice) throws -> ProcessLaunchResult {
        let before = try HerdrSessionProjection(snapshot: api.snapshot())
        let client = HerdrActionClient(api: api)
        let placementAction: HerdrAction
        switch placement {
        case .split(let targetPaneID, let direction, let cwd):
            placementAction = .paneSplit(targetPaneID: targetPaneID, direction: direction, ratio: 0.5, cwd: cwd, focus: true)
        case .newTab(let workspaceID, let cwd):
            placementAction = .tabCreate(workspaceID: workspaceID, cwd: cwd, label: nil, focus: true)
        }
        let shellProjection = try client.perform(placementAction)
        let oldPaneIDs = Set(before.panes.map(\.id))
        guard let paneID = shellProjection.panes.first(where: { !oldPaneIDs.contains($0.id) })?.id else {
            throw HerdrClientError.unexpectedResponse("Herdr created no new pane for the requested process")
        }

        guard case .agent(let kind, let name, let args, let timeout) = process else {
            return ProcessLaunchResult(projection: shellProjection, paneID: paneID, agentStarted: false, agentError: nil)
        }
        let agentAction = HerdrAction.agentStart(paneID: paneID, kind: kind, name: name, args: args, timeoutMilliseconds: timeout)
        do {
            return ProcessLaunchResult(
                projection: try client.perform(agentAction),
                paneID: paneID,
                agentStarted: true,
                agentError: nil
            )
        } catch {
            return ProcessLaunchResult(
                projection: shellProjection,
                paneID: paneID,
                agentStarted: false,
                agentError: error.localizedDescription
            )
        }
    }
}
