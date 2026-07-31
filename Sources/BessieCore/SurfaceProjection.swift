import Foundation

public enum AgentSemanticState: String, Codable, CaseIterable, Equatable, Sendable {
    case blocked, working, done, idle, unknown

    public init(herdrValue: String) {
        self = Self(rawValue: herdrValue.lowercased()) ?? .unknown
    }

    public var needsAttention: Bool { self == .blocked || self == .done }
}

public enum AttentionProvenance: String, Codable, Equatable, Sendable { case herdr }
public enum AttentionAction: Equatable, Sendable { case openPane(paneID: String) }

public struct PaneOpenTarget: Equatable, Sendable {
    public let workspaceID: String
    public let tabID: String
    public let paneID: String

    public init(workspaceID: String, tabID: String, paneID: String) {
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.paneID = paneID
    }
}

public struct PaneMoveChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let destination: PaneMoveDestination

    public init(id: String, title: String, destination: PaneMoveDestination) {
        self.id = id
        self.title = title
        self.destination = destination
    }
}

public struct PaneMoveChoices: Equatable, Sendable {
    public let tabs: [PaneMoveChoice]
    public let workspaces: [PaneMoveChoice]
    public let newTab: PaneMoveDestination
    public let newWorkspace: PaneMoveDestination

    public init?(projection: HerdrSessionProjection, paneID: String) {
        guard let pane = projection.panes.first(where: { $0.id == paneID }) else { return nil }

        tabs = projection.tabs
            .filter { $0.workspaceID == pane.workspaceID && $0.id != pane.tabID }
            .sorted { $0.number < $1.number }
            .map { tab in
                let targetPane = projection.panes.first { $0.tabID == tab.id && $0.focused }
                    ?? projection.panes.first { $0.tabID == tab.id }
                return PaneMoveChoice(
                    id: tab.id,
                    title: tab.label,
                    destination: .tab(
                        tabID: tab.id,
                        targetPaneID: targetPane?.id,
                        split: .right,
                        ratio: 0.5
                    )
                )
            }

        workspaces = projection.workspaces
            .filter { $0.id != pane.workspaceID }
            .sorted { $0.number < $1.number }
            .map {
                PaneMoveChoice(
                    id: $0.id,
                    title: $0.label,
                    destination: .newTab(workspaceID: $0.id, label: nil)
                )
            }

        newTab = .newTab(workspaceID: pane.workspaceID, label: nil)
        newWorkspace = .newWorkspace(label: nil, tabLabel: nil)
    }
}

public struct WorkspaceSurfaceSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let number: Int
    public let label: String
    public let tabCount: Int
    public let paneCount: Int
    public let rolledState: AgentSemanticState
    public let attentionCount: Int
    public let focused: Bool
}

public struct AttentionSurfaceItem: Identifiable, Equatable, Sendable {
    public var id: String { paneID }
    public let paneID: String
    public let state: AgentSemanticState
    public let identity: String
    public let location: String
    public let provenance: AttentionProvenance
    public let action: AttentionAction
}

public struct BessieSurfaceProjection: Equatable, Sendable {
    public let workspaces: [WorkspaceSurfaceSummary]
    public let attention: [AttentionSurfaceItem]
    public let notificationPanes: [BessieNotificationPane]
    private let targets: [String: PaneOpenTarget]

    public init(projection: HerdrSessionProjection) {
        let tabsByID = Dictionary(uniqueKeysWithValues: projection.tabs.map { ($0.id, $0) })
        let workspacesByID = Dictionary(uniqueKeysWithValues: projection.workspaces.map { ($0.id, $0) })
        let panesByWorkspace = Dictionary(grouping: projection.panes, by: \.workspaceID)

        workspaces = projection.workspaces.map { workspace in
            let panes = panesByWorkspace[workspace.id] ?? []
            let states = panes.map { AgentSemanticState(herdrValue: $0.agentStatus) }
            return WorkspaceSurfaceSummary(
                id: workspace.id,
                number: workspace.number,
                label: workspace.label,
                tabCount: workspace.tabCount,
                paneCount: workspace.paneCount,
                rolledState: Self.highest(states, fallback: AgentSemanticState(herdrValue: workspace.agentStatus)),
                attentionCount: states.filter(\.needsAttention).count,
                focused: workspace.focused
            )
        }

        notificationPanes = projection.panes.compactMap { pane in
            guard let workspace = workspacesByID[pane.workspaceID],
                  let tab = tabsByID[pane.tabID]
            else { return nil }
            let paneLabel = pane.label ?? pane.title ?? pane.agent ?? "Untitled pane"
            return BessieNotificationPane(
                paneID: pane.id,
                state: AgentSemanticState(herdrValue: pane.agentStatus),
                revision: pane.revision,
                identity: pane.agent ?? pane.label ?? pane.title ?? "Untitled pane",
                location: "\(workspace.label) / \(tab.label) / \(paneLabel)",
                target: PaneOpenTarget(workspaceID: pane.workspaceID, tabID: pane.tabID, paneID: pane.id)
            )
        }

        attention = projection.panes.compactMap { pane in
            let state = AgentSemanticState(herdrValue: pane.agentStatus)
            guard state.needsAttention,
                  let workspace = workspacesByID[pane.workspaceID],
                  let tab = tabsByID[pane.tabID]
            else { return nil }
            let paneLabel = pane.label ?? pane.title ?? pane.agent ?? "Untitled pane"
            return AttentionSurfaceItem(
                paneID: pane.id,
                state: state,
                identity: pane.agent ?? pane.label ?? pane.title ?? "Untitled pane",
                location: "\(workspace.label) / \(tab.label) / \(paneLabel)",
                provenance: .herdr,
                action: .openPane(paneID: pane.id)
            )
        }.sorted { Self.rank($0.state) < Self.rank($1.state) }

        targets = Dictionary(uniqueKeysWithValues: projection.panes.map {
            ($0.id, PaneOpenTarget(workspaceID: $0.workspaceID, tabID: $0.tabID, paneID: $0.id))
        })
    }

    public func openTarget(paneID: String) -> PaneOpenTarget? { targets[paneID] }

    private static func highest(_ states: [AgentSemanticState], fallback: AgentSemanticState) -> AgentSemanticState {
        states.min { rank($0) < rank($1) } ?? fallback
    }

    private static func rank(_ state: AgentSemanticState) -> Int {
        switch state {
        case .blocked: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        case .unknown: 4
        }
    }
}
