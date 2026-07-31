import Foundation

public struct BessieNotificationPane: Equatable, Sendable {
    public let paneID: String
    public let state: AgentSemanticState
    public let revision: UInt64
    public let identity: String
    public let location: String
    public let target: PaneOpenTarget

    public init(
        paneID: String,
        state: AgentSemanticState,
        revision: UInt64,
        identity: String,
        location: String,
        target: PaneOpenTarget
    ) {
        self.paneID = paneID
        self.state = state
        self.revision = revision
        self.identity = identity
        self.location = location
        self.target = target
    }
}

public struct BessieNotificationEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let target: PaneOpenTarget

    public init(id: String, title: String, body: String, target: PaneOpenTarget) {
        self.id = id
        self.title = title
        self.body = body
        self.target = target
    }
}

public enum BessieNotificationRoute {
    public static func resolve(
        pending: PaneOpenTarget,
        projection: HerdrSessionProjection
    ) -> PaneOpenTarget? {
        BessieSurfaceProjection(projection: projection).openTarget(paneID: pending.paneID)
    }
}

public struct BessieNotificationPlanner: Sendable {
    private var seeded = false
    private var previousStates: [String: AgentSemanticState] = [:]

    public init() {}

    public mutating func events(
        for panes: [BessieNotificationPane],
        policy: BessieNotifications,
        activePaneID: String?
    ) -> [BessieNotificationEvent] {
        let nextStates = Dictionary(uniqueKeysWithValues: panes.map { ($0.paneID, $0.state) })
        defer {
            previousStates = nextStates
            seeded = true
        }

        guard seeded else { return [] }

        return panes.compactMap { pane in
            guard previousStates[pane.paneID] != pane.state,
                  pane.paneID != activePaneID,
                  policy.allows(pane.state)
            else { return nil }

            let title: String
            switch pane.state {
            case .blocked:
                title = "\(pane.identity) needs you"
            case .done:
                title = "\(pane.identity) is done"
            default:
                return nil
            }

            return BessieNotificationEvent(
                id: "bessie.\(pane.paneID).\(pane.state.rawValue).\(pane.revision)",
                title: title,
                body: pane.location,
                target: pane.target
            )
        }
    }
}

private extension BessieNotifications {
    func allows(_ state: AgentSemanticState) -> Bool {
        switch (self, state) {
        case (.blockedOnly, .blocked), (.blockedAndDone, .blocked), (.blockedAndDone, .done):
            true
        default:
            false
        }
    }
}
