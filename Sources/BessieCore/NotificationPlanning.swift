import Foundation

public struct BessieNotificationPane: Equatable, Sendable {
    public let paneID: String
    public let terminalID: String
    public let state: AgentSemanticState
    public let revision: UInt64
    public let identity: String
    public let location: String
    public let target: PaneOpenTarget

    public init(
        paneID: String,
        terminalID: String? = nil,
        state: AgentSemanticState,
        revision: UInt64,
        identity: String,
        location: String,
        target: PaneOpenTarget
    ) {
        self.paneID = paneID
        self.terminalID = terminalID ?? paneID
        self.state = state
        self.revision = revision
        self.identity = identity
        self.location = location
        self.target = target
    }
}

public struct BessieNotificationEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let terminalID: String
    public let state: AgentSemanticState
    public let title: String
    public let body: String
    public let target: PaneOpenTarget

    public init(
        id: String,
        terminalID: String,
        state: AgentSemanticState,
        title: String,
        body: String,
        target: PaneOpenTarget
    ) {
        self.id = id
        self.terminalID = terminalID
        self.state = state
        self.title = title
        self.body = body
        self.target = target
    }
}

public struct BessieNotificationDeepLink: Equatable, Sendable {
    private static let connectionKey = "connection_id"
    private static let workspaceKey = "workspace_id"
    private static let tabKey = "tab_id"
    private static let paneKey = "pane_id"

    public let target: RoutedPaneTarget

    public init(target: RoutedPaneTarget) {
        self.target = target
    }

    public init?(userInfo: [String: String]) {
        guard let connectionID = userInfo[Self.connectionKey],
              let workspaceID = userInfo[Self.workspaceKey],
              let tabID = userInfo[Self.tabKey],
              let paneID = userInfo[Self.paneKey]
        else { return nil }
        target = RoutedPaneTarget(
            connectionID: connectionID,
            workspaceID: workspaceID,
            tabID: tabID,
            paneID: paneID
        )
    }

    public init?(userInfo: [AnyHashable: Any]) {
        self.init(userInfo: Dictionary(uniqueKeysWithValues: userInfo.compactMap { key, value in
            guard let key = key as? String, let value = value as? String else { return nil }
            return (key, value)
        }))
    }

    public var userInfo: [String: String] {
        [
            Self.connectionKey: target.connectionID,
            Self.workspaceKey: target.workspaceID,
            Self.tabKey: target.tabID,
            Self.paneKey: target.paneID,
        ]
    }
}

public enum BessieNotificationRoute {
    public static func resolve(
        pending: RoutedPaneTarget,
        connectionID: String,
        projection: HerdrSessionProjection
    ) -> PaneOpenTarget? {
        guard pending.connectionID == connectionID,
              let current = BessieSurfaceProjection(projection: projection).openTarget(paneID: pending.paneID),
              current.workspaceID == pending.workspaceID,
              current.tabID == pending.tabID
        else { return nil }
        return current
    }
}

public struct BessieNotificationPlanner: Sendable {
    private struct PaneIncarnation: Hashable, Sendable {
        let paneID: String
        let terminalID: String
    }

    private var seeded = false
    private var previousStates: [PaneIncarnation: AgentSemanticState] = [:]

    public init() {}

    public mutating func events(
        for panes: [BessieNotificationPane],
        policy: BessieNotifications,
        activePaneID: String?,
        suppressedPaneIDs: Set<String> = [],
        connectionLabel: String? = nil
    ) -> [BessieNotificationEvent] {
        let nextStates = Dictionary(uniqueKeysWithValues: panes.map {
            (PaneIncarnation(paneID: $0.paneID, terminalID: $0.terminalID), $0.state)
        })
        defer {
            previousStates = nextStates
            seeded = true
        }

        guard seeded else { return [] }

        return panes.compactMap { pane in
            let incarnation = PaneIncarnation(paneID: pane.paneID, terminalID: pane.terminalID)
            guard let previous = previousStates[incarnation],
                  previous != pane.state,
                  pane.paneID != activePaneID,
                  !suppressedPaneIDs.contains(pane.paneID),
                  policy.shouldNotify(transitioningTo: pane.state, from: previous)
            else { return nil }

            let title: String
            switch pane.state {
            case .blocked:
                title = "\(pane.identity) needs you"
            case .done:
                title = "\(pane.identity) is done"
            case .idle:
                // Settled completion for agents (e.g. Hermes) that land on idle, not done.
                title = "\(pane.identity) is settled"
            default:
                return nil
            }

            return BessieNotificationEvent(
                id: "bessie.\(pane.paneID).\(pane.terminalID).\(pane.state.rawValue).\(pane.revision)",
                terminalID: pane.terminalID,
                state: pane.state,
                title: title,
                body: connectionLabel.map { "\(pane.location) · \($0)" } ?? pane.location,
                target: pane.target
            )
        }
    }
}

private extension BessieNotifications {
    /// `blockedAndDone` ("Needs me and settled") treats UI Settled as `done` **or** `idle`.
    /// Settled toasts only fire when leaving an active state (`working` / `blocked`), so
    /// idle↔done churn inside Settled does not spam.
    func shouldNotify(transitioningTo state: AgentSemanticState, from previous: AgentSemanticState?) -> Bool {
        switch self {
        case .off:
            return false
        case .blockedOnly:
            return state == .blocked
        case .blockedAndDone:
            switch state {
            case .blocked:
                return true
            case .done, .idle:
                guard let previous else { return false }
                return previous == .working || previous == .blocked
            default:
                return false
            }
        }
    }
}
