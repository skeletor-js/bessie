import Foundation

public struct AttentionItemModel: Equatable, Identifiable, Sendable {
    public var id: String { "\(connectionID)::\(paneID)" }
    public let connectionID: String
    public let connectionLabel: String
    public let paneID: String
    public let state: AgentSemanticState
    public let identity: String
    public let location: String
    public let target: RoutedPaneTarget
}

public enum AttentionListBuilder {
    public static func items(
        from agents: [ConnectedAgentProjection],
        connectionLabels: [String: ConnectionDisplayLabel] = [:]
    ) -> [AttentionItemModel] {
        agents.compactMap { connected in
            let state = AgentSemanticState(herdrValue: connected.agent.agentStatus)
            guard state.needsAttention else { return nil }
            let label = connectionLabels[connected.connectionID]
                ?? ConnectionDisplayLabel(connection: connected.connection)
            return AttentionItemModel(
                connectionID: connected.connectionID,
                connectionLabel: label.short,
                paneID: connected.paneID,
                state: state,
                identity: connected.agent.identity,
                location: connected.presentationLocation,
                target: connected.routedPaneTarget
            )
        }.sorted(by: itemPrecedes)
    }

    private static func itemPrecedes(_ lhs: AttentionItemModel, _ rhs: AttentionItemModel) -> Bool {
        agentListPrecedes(
            lhs: (lhs.state, lhs.connectionLabel, lhs.identity, lhs.id),
            rhs: (rhs.state, rhs.connectionLabel, rhs.identity, rhs.id)
        )
    }
}
