import Foundation

/// An agent plus the Herdr connection that owns its raw workspace, tab, pane,
/// and terminal identifiers. The composite ID prevents collisions when two
/// independent Herdr sessions both contain values such as `w1:p1`.
public struct ConnectedAgentProjection: Equatable, Identifiable, Sendable {
    public let connection: BessieConnectionDefinition
    public let agent: AgentProjection
    public let workspaceLabel: String?
    public let tabLabel: String?

    public init(
        connection: BessieConnectionDefinition,
        agent: AgentProjection,
        workspaceLabel: String? = nil,
        tabLabel: String? = nil
    ) {
        self.connection = connection
        self.agent = agent
        self.workspaceLabel = workspaceLabel
        self.tabLabel = tabLabel
    }

    public var id: String { "\(connection.id)::\(agent.id)" }
    public var connectionID: String { connection.id }
    public var connectionName: String { connection.name }
    public var paneID: String { agent.id }
    public var workspaceID: String { agent.workspaceID }
    public var tabID: String { agent.tabID }

    var presentationLocation: String {
        "\(workspaceLabel ?? "Untitled workspace") · \(tabLabel ?? "Untitled tab")"
    }

    var routedPaneTarget: RoutedPaneTarget {
        RoutedPaneTarget(
            connectionID: connectionID,
            workspaceID: workspaceID,
            tabID: tabID,
            paneID: paneID
        )
    }
}

/// One currently tracked Herdr agent, independent of whether it is working,
/// idle, blocked, done, or temporarily unknown.
public struct AgentProjection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let terminalID: String
    public let workspaceID: String
    public let tabID: String
    public let focused: Bool
    public let label: String?
    public let agent: String?
    public let displayAgent: String?
    public let name: String?
    public let title: String?
    public let agentStatus: String
    public let revision: UInt64
    public let launchPending: Bool

    public var identity: String {
        name ?? label ?? displayAgent ?? agent ?? title ?? "Agent"
    }

    enum CodingKeys: String, CodingKey {
        case id = "pane_id"
        case terminalID = "terminal_id"
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
        case focused, label, agent, name, title, revision
        case displayAgent = "display_agent"
        case agentStatus = "agent_status"
        case launchPending = "launch_pending"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        terminalID = try values.decode(String.self, forKey: .terminalID)
        workspaceID = try values.decode(String.self, forKey: .workspaceID)
        tabID = try values.decode(String.self, forKey: .tabID)
        focused = try values.decodeIfPresent(Bool.self, forKey: .focused) ?? false
        label = try values.decodeIfPresent(String.self, forKey: .label)
        agent = try values.decodeIfPresent(String.self, forKey: .agent)
        displayAgent = try values.decodeIfPresent(String.self, forKey: .displayAgent)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        agentStatus = try values.decodeIfPresent(String.self, forKey: .agentStatus) ?? "unknown"
        revision = try values.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        launchPending = try values.decodeIfPresent(Bool.self, forKey: .launchPending) ?? false
    }

    public init(
        id: String,
        terminalID: String,
        workspaceID: String,
        tabID: String,
        focused: Bool,
        label: String?,
        agent: String?,
        displayAgent: String?,
        name: String?,
        title: String?,
        agentStatus: String,
        revision: UInt64,
        launchPending: Bool
    ) {
        self.id = id
        self.terminalID = terminalID
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.focused = focused
        self.label = label
        self.agent = agent
        self.displayAgent = displayAgent
        self.name = name
        self.title = title
        self.agentStatus = agentStatus
        self.revision = revision
        self.launchPending = launchPending
    }

    public init(pane: PaneProjection) {
        self.init(
            id: pane.id,
            terminalID: pane.terminalID,
            workspaceID: pane.workspaceID,
            tabID: pane.tabID,
            focused: pane.focused,
            label: pane.label,
            agent: pane.agent,
            displayAgent: nil,
            name: nil,
            title: pane.title,
            agentStatus: pane.agentStatus,
            revision: pane.revision,
            launchPending: false
        )
    }

    func merging(pane: PaneProjection?) -> AgentProjection {
        guard let pane else { return self }
        return AgentProjection(
            id: id,
            terminalID: terminalID,
            workspaceID: workspaceID,
            tabID: tabID,
            focused: focused,
            label: pane.label ?? label,
            agent: agent ?? pane.agent,
            displayAgent: displayAgent,
            name: name,
            title: title ?? pane.title,
            agentStatus: agentStatus,
            revision: max(revision, pane.revision),
            launchPending: launchPending
        )
    }
}
