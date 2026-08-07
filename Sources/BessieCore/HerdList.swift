import Foundation

public enum ConnectionScope: Equatable, Sendable {
    case all
    case connection(id: String)

    func includes(connectionID: String) -> Bool {
        switch self {
        case .all: true
        case .connection(let id): connectionID == id
        }
    }
}

public enum HerdListFilter: String, CaseIterable, Sendable {
    case all = "All"
    case needsYou = "Needs you"
    case working = "Working"
    case settled = "Settled"
    case unknown = "Unknown"

    public func includes(_ state: AgentSemanticState) -> Bool {
        switch self {
        case .all: true
        case .needsYou: state == .blocked
        case .working: state == .working
        case .settled: state == .done || state == .idle
        case .unknown: state == .unknown
        }
    }
}

public enum HerdPresentationStatus: String, Equatable, Sendable {
    case needsYou = "Needs you"
    case working = "Working"
    case settled = "Settled"
    case unknown = "Unknown"

    public init(state: AgentSemanticState) {
        switch state {
        case .blocked: self = .needsYou
        case .working: self = .working
        case .done, .idle: self = .settled
        case .unknown: self = .unknown
        }
    }

    var sortRank: Int {
        switch self {
        case .needsYou: 0
        case .working: 1
        case .settled: 2
        case .unknown: 3
        }
    }
}

public struct HerdPaneIdentity: Hashable, Codable, Sendable {
    public let connectionID: String
    public let paneID: String

    public init(connectionID: String, paneID: String) {
        self.connectionID = connectionID
        self.paneID = paneID
    }
}

public enum HerdRailGroup: String, CaseIterable, Equatable, Sendable {
    case needsYou = "Needs you"
    case working = "Working"
    case settled = "Settled"
    case unknown = "Unknown"
    case shells = "Shells"
}

public struct HerdRailPaneRow: Identifiable, Equatable, Sendable {
    public let id: HerdPaneIdentity
    public let terminalID: String
    public let title: String
    public let location: String
    public let group: HerdRailGroup
    public let rawState: AgentSemanticState
    public let agentKind: String?
    public let target: RoutedPaneTarget

    public var accessibilityDescription: String { "\(title), \(group.rawValue), \(location)" }
}

public struct HerdRailConnectionInput: Sendable {
    public let connection: BessieConnectionDefinition
    public let projection: HerdrSessionProjection?
    public let isFresh: Bool

    public init(connection: BessieConnectionDefinition, projection: HerdrSessionProjection?, isFresh: Bool) {
        self.connection = connection
        self.projection = projection
        self.isFresh = isFresh
    }
}

public struct HerdRailProjection: Equatable, Sendable {
    public let rows: [HerdRailPaneRow]

    public init(connections: [HerdRailConnectionInput], scope: ConnectionScope = .all) {
        rows = connections
            .filter {
                $0.connection.enabled
                    && $0.isFresh
                    && scope.includes(connectionID: $0.connection.id)
            }
            .flatMap(Self.project)
            .sorted(by: Self.precedes)
    }

    public init(rows: [HerdRailPaneRow]) {
        self.rows = rows
    }

    /// Sidebar hierarchy selections only filter the ordinary pane rail.
    /// A nil identifier broadens that level instead of changing presentation mode.
    public func filtered(
        connectionID: String?,
        workspaceID: String?,
        tabID: String? = nil
    ) -> HerdRailProjection {
        return HerdRailProjection(rows: rows.filter {
            (connectionID == nil || $0.target.connectionID == connectionID)
                && (workspaceID == nil || $0.target.workspaceID == workspaceID)
                && (tabID == nil || $0.target.tabID == tabID)
        })
    }

    public func rows(in group: HerdRailGroup) -> [HerdRailPaneRow] { rows.filter { $0.group == group } }
    public func count(in group: HerdRailGroup) -> Int { rows(in: group).count }
    public var traversal: HerdPaneTraversal { HerdPaneTraversal(rows.map(\.id)) }

    private static func project(_ input: HerdRailConnectionInput) -> [HerdRailPaneRow] {
        guard let projection = input.projection else { return [] }
        let workspaces = Dictionary(uniqueKeysWithValues: projection.workspaces.map { ($0.id, $0.label) })
        let tabs = Dictionary(uniqueKeysWithValues: projection.tabs.map { ($0.id, $0.label) })
        let agents = Dictionary(projection.agents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return projection.panes.map { pane in
            let agent = agents[pane.id]
            let state = AgentSemanticState(herdrValue: agent?.agentStatus ?? pane.agentStatus)
            let group: HerdRailGroup
            if agent == nil { group = .shells }
            else {
                switch HerdPresentationStatus(state: state) {
                case .needsYou: group = .needsYou
                case .working: group = .working
                case .settled: group = .settled
                case .unknown: group = .unknown
                }
            }
            let title = agent?.identity ?? pane.presentationTitle
            let location = [ConnectionDisplayLabel(connection: input.connection).short,
                            workspaces[pane.workspaceID], tabs[pane.tabID]]
                .compactMap { $0 }.joined(separator: " · ")
            return HerdRailPaneRow(
                id: HerdPaneIdentity(connectionID: input.connection.id, paneID: pane.id),
                terminalID: pane.terminalID,
                title: title, location: location, group: group, rawState: state,
                agentKind: agent?.agent ?? agent?.displayAgent,
                target: RoutedPaneTarget(connectionID: input.connection.id, workspaceID: pane.workspaceID,
                                         tabID: pane.tabID, paneID: pane.id)
            )
        }
    }

    private static func precedes(_ lhs: HerdRailPaneRow, _ rhs: HerdRailPaneRow) -> Bool {
        let ranks = Dictionary(uniqueKeysWithValues: HerdRailGroup.allCases.enumerated().map { ($1, $0) })
        if lhs.group != rhs.group { return ranks[lhs.group, default: 0] < ranks[rhs.group, default: 0] }
        let location = lhs.location.localizedCaseInsensitiveCompare(rhs.location)
        if location != .orderedSame { return location == .orderedAscending }
        let title = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if title != .orderedSame { return title == .orderedAscending }
        if lhs.id.connectionID != rhs.id.connectionID { return lhs.id.connectionID < rhs.id.connectionID }
        return lhs.id.paneID < rhs.id.paneID
    }
}

public struct HerdPaneTraversal: Equatable, Sendable {
    public enum Direction: Sendable { case previous, next }
    public let paneIDs: [HerdPaneIdentity]

    public init(_ paneIDs: [HerdPaneIdentity]) { self.paneIDs = paneIDs }

    public func target(from current: HerdPaneIdentity?, direction: Direction) -> HerdPaneIdentity? {
        guard !paneIDs.isEmpty else { return nil }
        guard paneIDs.count > 1 else { return paneIDs[0] }
        guard let current, let index = paneIDs.firstIndex(of: current) else {
            return direction == .next ? paneIDs[0] : paneIDs[paneIDs.count - 1]
        }
        switch direction {
        case .next: return paneIDs[(index + 1) % paneIDs.count]
        case .previous: return paneIDs[(index - 1 + paneIDs.count) % paneIDs.count]
        }
    }
}

public struct HerdCardModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let connectionID: String
    public let connectionLabel: String
    public let connectionDetail: String
    public let identity: String
    public let agentKind: String?
    public let state: AgentSemanticState
    public let location: String
    public let activity: String?
    public let paneTarget: RoutedPaneTarget

    public init(
        id: String,
        connectionID: String,
        connectionLabel: String,
        connectionDetail: String,
        identity: String,
        agentKind: String?,
        state: AgentSemanticState,
        location: String,
        activity: String?,
        paneTarget: RoutedPaneTarget
    ) {
        self.id = id
        self.connectionID = connectionID
        self.connectionLabel = connectionLabel
        self.connectionDetail = connectionDetail
        self.identity = identity
        self.agentKind = agentKind
        self.state = state
        self.location = location
        self.activity = activity
        self.paneTarget = paneTarget
    }

    public var presentationStatus: HerdPresentationStatus { HerdPresentationStatus(state: state) }
}

public enum HerdListBuilder {
    public static func cards(
        agents: [ConnectedAgentProjection],
        connectedConnectionIDs: Set<String>,
        scope: ConnectionScope = .all,
        filter: HerdListFilter,
        connectionLabels: [String: ConnectionDisplayLabel] = [:]
    ) -> [HerdCardModel] {
        agents.compactMap { connected in
            let state = AgentSemanticState(herdrValue: connected.agent.agentStatus)
            guard connectedConnectionIDs.contains(connected.connectionID),
                  scope.includes(connectionID: connected.connectionID),
                  filter.includes(state)
            else { return nil }
            let label = connectionLabels[connected.connectionID]
                ?? ConnectionDisplayLabel(connection: connected.connection)
            return HerdCardModel(
                id: connected.id,
                connectionID: connected.connectionID,
                connectionLabel: label.short,
                connectionDetail: label.detail,
                identity: connected.agent.identity,
                agentKind: connected.agent.displayAgent ?? connected.agent.agent,
                state: state,
                location: connected.presentationLocation,
                activity: connected.agent.title?.trimmedOrNil,
                paneTarget: connected.routedPaneTarget
            )
        }.sorted(by: cardPrecedes)
    }

    public static func counts(
        agents: [ConnectedAgentProjection],
        connectedConnectionIDs: Set<String>,
        scope: ConnectionScope = .all
    ) -> [HerdListFilter: Int] {
        var result = Dictionary(uniqueKeysWithValues: HerdListFilter.allCases.map { ($0, 0) })
        let liveAgents = agents.filter {
            connectedConnectionIDs.contains($0.connectionID)
                && scope.includes(connectionID: $0.connectionID)
        }
        result[.all] = liveAgents.count
        for agent in liveAgents {
            let state = AgentSemanticState(herdrValue: agent.agent.agentStatus)
            for filter in HerdListFilter.allCases where filter != .all && filter.includes(state) {
                result[filter, default: 0] += 1
            }
        }
        return result
    }

    private static func cardPrecedes(_ lhs: HerdCardModel, _ rhs: HerdCardModel) -> Bool {
        agentListPrecedes(
            lhs: (lhs.state, lhs.connectionLabel, lhs.location, lhs.identity, lhs.id),
            rhs: (rhs.state, rhs.connectionLabel, rhs.location, rhs.identity, rhs.id)
        )
    }
}

func agentListPrecedes(
    lhs: (state: AgentSemanticState, connection: String, location: String, identity: String, id: String),
    rhs: (state: AgentSemanticState, connection: String, location: String, identity: String, id: String)
) -> Bool {
    let lhsStatus = HerdPresentationStatus(state: lhs.state)
    let rhsStatus = HerdPresentationStatus(state: rhs.state)
    if lhsStatus.sortRank != rhsStatus.sortRank { return lhsStatus.sortRank < rhsStatus.sortRank }
    let connectionOrder = lhs.connection.localizedCaseInsensitiveCompare(rhs.connection)
    if connectionOrder != .orderedSame { return connectionOrder == .orderedAscending }
    let locationOrder = lhs.location.localizedCaseInsensitiveCompare(rhs.location)
    if locationOrder != .orderedSame { return locationOrder == .orderedAscending }
    let identityOrder = lhs.identity.localizedCaseInsensitiveCompare(rhs.identity)
    if identityOrder != .orderedSame { return identityOrder == .orderedAscending }
    return lhs.id < rhs.id
}
