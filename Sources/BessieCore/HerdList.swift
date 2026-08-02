import Foundation

public enum HerdListFilter: String, CaseIterable, Sendable {
    case all = "All"
    case needsYou = "Needs you"
    case working = "Working"
    case done = "Done"
    case idle = "Idle"

    public func includes(_ state: AgentSemanticState) -> Bool {
        switch self {
        case .all: true
        case .needsYou: state == .blocked
        case .working: state == .working
        case .done: state == .done
        case .idle: state == .idle
        }
    }
}

public struct HerdCardModel: Equatable, Identifiable, Sendable {
    public let id: String
    public let connectionID: String
    public let connectionLabel: String
    public let connectionDetail: String
    public let identity: String
    public let state: AgentSemanticState
    public let location: String
    public let activity: String?
    public let paneTarget: RoutedPaneTarget
}

public enum HerdListBuilder {
    public static func cards(
        agents: [ConnectedAgentProjection],
        filter: HerdListFilter,
        connectionLabels: [String: ConnectionDisplayLabel] = [:]
    ) -> [HerdCardModel] {
        agents.compactMap { connected in
            let state = AgentSemanticState(herdrValue: connected.agent.agentStatus)
            guard filter.includes(state) else { return nil }
            let label = connectionLabels[connected.connectionID]
                ?? ConnectionDisplayLabel(connection: connected.connection)
            return HerdCardModel(
                id: connected.id,
                connectionID: connected.connectionID,
                connectionLabel: label.short,
                connectionDetail: label.detail,
                identity: connected.agent.identity,
                state: state,
                location: connected.presentationLocation,
                activity: connected.agent.title?.trimmedOrNil,
                paneTarget: connected.routedPaneTarget
            )
        }.sorted(by: cardPrecedes)
    }

    public static func counts(agents: [ConnectedAgentProjection]) -> [HerdListFilter: Int] {
        var result = Dictionary(uniqueKeysWithValues: HerdListFilter.allCases.map { ($0, 0) })
        result[.all] = agents.count
        for agent in agents {
            let state = AgentSemanticState(herdrValue: agent.agent.agentStatus)
            for filter in HerdListFilter.allCases where filter != .all && filter.includes(state) {
                result[filter, default: 0] += 1
            }
        }
        return result
    }

    private static func cardPrecedes(_ lhs: HerdCardModel, _ rhs: HerdCardModel) -> Bool {
        agentListPrecedes(
            lhs: (lhs.state, lhs.connectionLabel, lhs.identity, lhs.id),
            rhs: (rhs.state, rhs.connectionLabel, rhs.identity, rhs.id)
        )
    }
}

func agentListPrecedes(
    lhs: (state: AgentSemanticState, connection: String, identity: String, id: String),
    rhs: (state: AgentSemanticState, connection: String, identity: String, id: String)
) -> Bool {
    if lhs.state.sortRank != rhs.state.sortRank { return lhs.state.sortRank < rhs.state.sortRank }
    let connectionOrder = lhs.connection.localizedCaseInsensitiveCompare(rhs.connection)
    if connectionOrder != .orderedSame { return connectionOrder == .orderedAscending }
    let identityOrder = lhs.identity.localizedCaseInsensitiveCompare(rhs.identity)
    if identityOrder != .orderedSame { return identityOrder == .orderedAscending }
    return lhs.id < rhs.id
}
