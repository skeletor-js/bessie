import Foundation
import XCTest
@testable import BessieApp
@testable import BessieCore

final class SurfaceProjectionTests: XCTestCase {
    func testConnectedAgentsRemainDistinctWhenSessionsReusePaneIDs() throws {
        let agent = AgentProjection(
            id: "p1", terminalID: "term-1", workspaceID: "w1", tabID: "t1",
            focused: false, label: "Hermes", agent: "hermes", displayAgent: "Hermes",
            name: nil, title: nil, agentStatus: "working", revision: 1, launchPending: false
        )

        let local = ConnectedAgentProjection(connection: .localBessie, agent: agent)
        let remote = ConnectedAgentProjection(
            connection: try BessieConnectionDefinition(
                id: "remote", name: "Hermes VPS", kind: .ssh, sshHost: "hermes", session: nil
            ).validated(),
            agent: agent
        )

        XCTAssertNotEqual(local.id, remote.id)
        XCTAssertEqual(local.paneID, "p1")
        XCTAssertEqual(remote.paneID, "p1")
        XCTAssertEqual(remote.connectionName, "Hermes VPS")
    }

    func testHerdUsesAuthoritativeAgentRosterAcrossWorkspacesAndEveryState() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)

        XCTAssertEqual(projection.agents.map(\.id), ["p1", "p3", "p2"])
        XCTAssertEqual(projection.agents.prefix(2).map(\.workspaceID), ["w1", "w2"])
        XCTAssertEqual(projection.agents.prefix(2).map(\.agentStatus), ["idle", "unknown"])
        XCTAssertEqual(projection.agents.prefix(2).map(\.identity), ["Codex one", "Claude two"])
    }

    func testWorkspaceRollupsAndAttentionUseOnlyAuthoritativePaneState() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let surfaces = BessieSurfaceProjection(projection: projection)

        XCTAssertEqual(surfaces.workspaces.map(\.label), ["alpha", "beta"])
        XCTAssertEqual(surfaces.workspaces[0].rolledState, .blocked)
        XCTAssertEqual(surfaces.workspaces[0].attentionCount, 2)
        XCTAssertEqual(surfaces.workspaces[1].rolledState, .idle)
        XCTAssertEqual(surfaces.attention.map(\.state), [.blocked, .done])
        XCTAssertEqual(surfaces.attention[0].location, "alpha / build / blocked pane")
        XCTAssertEqual(surfaces.attention[0].provenance, .herdr)
        XCTAssertEqual(surfaces.attention[0].action, .openPane(paneID: "p1"))
        XCTAssertEqual(surfaces.notificationPanes.map(\.paneID), ["p1", "p2", "p3"])
        XCTAssertEqual(surfaces.notificationPanes[0].target, PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1"))

        let connectedPanes = projection.panes.map {
            ConnectedAgentProjection(connection: .localBessie, agent: AgentProjection(pane: $0))
        }
        XCTAssertEqual(AttentionListBuilder.items(from: connectedPanes).map(\.state), [.blocked, .done])
    }

    func testPreferencesRoundTripEveryApprovedV1SettingAndDecodeLegacyValues() throws {
        let preferences = BessiePreferences(
            appearance: .light,
            density: .compact,
            appIcon: .light,
            cowprintEnabled: false,
            cowPrintIntensity: 0.08,
            cowPrintMotion: false,
            terminalFontSize: 15,
            paneGap: 6,
            notifications: .blockedAndDone,
            startupBehavior: .lastWorkspace
        )
        XCTAssertEqual(try JSONDecoder().decode(BessiePreferences.self, from: JSONEncoder().encode(preferences)), preferences)

        let legacy = Data(#"{"terminalFontSize":14,"paneGap":7}"#.utf8)
        let decoded = try JSONDecoder().decode(BessiePreferences.self, from: legacy)
        XCTAssertEqual(decoded.terminalFontSize, 14)
        XCTAssertEqual(decoded.paneGap, 7)
        XCTAssertEqual(decoded.appearance, .system)
        XCTAssertEqual(decoded.density, .comfortable)
        XCTAssertEqual(decoded.appIcon, .dark)
        XCTAssertTrue(decoded.cowprintEnabled)
        XCTAssertEqual(decoded.notifications, .blockedOnly)
    }

    func testOpenPaneTargetComesFromCurrentProjection() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let target = try XCTUnwrap(BessieSurfaceProjection(projection: projection).openTarget(paneID: "p2"))

        XCTAssertEqual(target.workspaceID, "w1")
        XCTAssertEqual(target.tabID, "t1")
        XCTAssertEqual(target.paneID, "p2")
        XCTAssertNil(BessieSurfaceProjection(projection: projection).openTarget(paneID: "missing"))
    }

    func testPaneMoveChoicesUseCurrentTopologyWithoutGuessingDestinations() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)
        let choices = try XCTUnwrap(PaneMoveChoices(projection: projection, paneID: "p1"))

        XCTAssertEqual(choices.tabs.map(\.title), ["review"])
        XCTAssertEqual(
            choices.tabs.first?.destination,
            .tab(tabID: "t2", targetPaneID: "p2", split: .right, ratio: 0.5)
        )
        XCTAssertEqual(choices.workspaces.map(\.title), ["beta"])
        XCTAssertEqual(choices.workspaces.first?.destination, .newTab(workspaceID: "w2", label: nil))
        XCTAssertEqual(choices.newTab, .newTab(workspaceID: "w1", label: nil))
        XCTAssertEqual(choices.newWorkspace, .newWorkspace(label: nil, tabLabel: nil))
        XCTAssertNil(PaneMoveChoices(projection: projection, paneID: "missing"))
    }

    func testNotificationPlannerSeedsThenEmitsOnlyNewAllowedTransitions() {
        var planner = BessieNotificationPlanner()
        let blocked = BessieNotificationPane(
            paneID: "p1", state: .blocked, revision: 1,
            identity: "Claude", location: "alpha / build / Claude",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        let done = BessieNotificationPane(
            paneID: "p2", state: .done, revision: 1,
            identity: "Codex", location: "alpha / review / Codex",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t2", paneID: "p2")
        )

        XCTAssertEqual(planner.events(for: [blocked, done], policy: .blockedAndDone, activePaneID: nil), [])

        let idle = BessieNotificationPane(
            paneID: "p1", state: .idle, revision: 2,
            identity: blocked.identity, location: blocked.location, target: blocked.target
        )
        let working = BessieNotificationPane(
            paneID: "p2", state: .working, revision: 2,
            identity: done.identity, location: done.location, target: done.target
        )
        XCTAssertEqual(planner.events(for: [idle, working], policy: .blockedAndDone, activePaneID: nil), [])

        let blockedAgain = BessieNotificationPane(
            paneID: "p1", state: .blocked, revision: 3,
            identity: blocked.identity, location: blocked.location, target: blocked.target
        )
        let doneAgain = BessieNotificationPane(
            paneID: "p2", state: .done, revision: 3,
            identity: done.identity, location: done.location, target: done.target
        )
        let events = planner.events(
            for: [blockedAgain, doneAgain],
            policy: .blockedAndDone,
            activePaneID: "p2",
            connectionLabel: "Hermes VPS"
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Claude needs you")
        XCTAssertEqual(events.first?.body, "alpha / build / Claude · Hermes VPS")
        XCTAssertEqual(events.first?.target, blocked.target)
        XCTAssertEqual(planner.events(for: [blockedAgain, doneAgain], policy: .blockedAndDone, activePaneID: nil), [])
    }

    func testNotificationDeepLinkRoundTripsFrozenFleetSchema() throws {
        let target = RoutedPaneTarget(
            connectionID: "remote",
            workspaceID: "w1",
            tabID: "t1",
            paneID: "p1"
        )
        let deepLink = BessieNotificationDeepLink(target: target)

        XCTAssertEqual(deepLink.userInfo, [
            "connection_id": "remote",
            "workspace_id": "w1",
            "tab_id": "t1",
            "pane_id": "p1",
        ])
        XCTAssertEqual(BessieNotificationDeepLink(userInfo: deepLink.userInfo)?.target, target)
        XCTAssertNil(BessieNotificationDeepLink(userInfo: [
            "workspace_id": "w1",
            "tab_id": "t1",
            "pane_id": "p1",
        ]))
    }

    func testNotificationRouteQueueUsesTapIdentityAndNewTapReplacesFallback() {
        let target = RoutedPaneTarget(
            connectionID: "remote",
            workspaceID: "w1",
            tabID: "t1",
            paneID: "p1"
        )
        let first = PendingNotificationRoute(id: UUID(), target: target)
        let second = PendingNotificationRoute(id: UUID(), target: target)
        var queue = NotificationRouteQueue()

        queue.enqueue(first)
        queue.enqueue(second)
        queue.consume(first)
        XCTAssertEqual(queue.pending, second)

        queue.fallBackToAttention(first)
        XCTAssertNil(queue.attentionFallback)
        queue.fallBackToAttention(second)
        XCTAssertEqual(queue.attentionFallback, second)

        let third = PendingNotificationRoute(id: UUID(), target: target)
        queue.enqueue(third)
        XCTAssertEqual(queue.pending, third)
        XCTAssertNil(queue.attentionFallback)
    }

    @MainActor
    func testNotificationConnectionWaitsForFleetInitialization() {
        let fleet = ConnectionFleetViewModel()
        XCTAssertEqual(fleet.notificationConnectionState(connectionID: "remote"), .waiting)
    }

    func testNotificationPlannerHonorsPolicyWithoutRetroactiveDelivery() {
        var planner = BessieNotificationPlanner()
        let idle = BessieNotificationPane(
            paneID: "p1", state: .idle, revision: 1,
            identity: "Claude", location: "alpha / build / Claude",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        _ = planner.events(for: [idle], policy: .blockedOnly, activePaneID: nil)
        let done = BessieNotificationPane(
            paneID: "p1", state: .done, revision: 2,
            identity: idle.identity, location: idle.location, target: idle.target
        )
        XCTAssertEqual(planner.events(for: [done], policy: .blockedOnly, activePaneID: nil), [])
        XCTAssertEqual(planner.events(for: [done], policy: .blockedAndDone, activePaneID: nil), [])
    }

    func testNotificationRouteRequiresOwningConnectionAndCurrentExactTopology() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let target = RoutedPaneTarget(
            connectionID: "remote",
            workspaceID: "w2",
            tabID: "t2",
            paneID: "p3"
        )
        let current = BessieNotificationRoute.resolve(
            pending: target,
            connectionID: "remote",
            projection: projection
        )

        XCTAssertEqual(current, PaneOpenTarget(workspaceID: "w2", tabID: "t2", paneID: "p3"))
        XCTAssertNil(BessieNotificationRoute.resolve(pending: target, connectionID: "local-bessie", projection: projection))
        XCTAssertNil(
            BessieNotificationRoute.resolve(
                pending: RoutedPaneTarget(
                    connectionID: "remote",
                    workspaceID: "stale",
                    tabID: "t2",
                    paneID: "p3"
                ),
                connectionID: "remote",
                projection: projection
            )
        )
    }

    func testDragPayloadsProduceOnlyValidSameCollectionReorders() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)

        let workspacePayload = BessieDragPayload.workspace(id: "w2")
        XCTAssertEqual(BessieDragPayload(encoded: workspacePayload.encoded), workspacePayload)
        XCTAssertEqual(BessieReorderDrop.workspaceAction(payload: workspacePayload, over: "w1", projection: projection), .workspaceMove(id: "w2", insertIndex: 0))
        XCTAssertEqual(BessieReorderDrop.workspaceAction(payload: .workspace(id: "w1"), over: "w2", projection: projection), .workspaceMove(id: "w1", insertIndex: 2))
        XCTAssertNil(BessieReorderDrop.workspaceAction(payload: workspacePayload, over: "w2", projection: projection))

        let tabPayload = BessieDragPayload.tab(id: "t2", workspaceID: "w1")
        XCTAssertEqual(BessieDragPayload(encoded: tabPayload.encoded), tabPayload)
        XCTAssertEqual(BessieReorderDrop.tabAction(payload: tabPayload, over: "t1", workspaceID: "w1", projection: projection), .tabMove(id: "t2", insertIndex: 0))
        XCTAssertEqual(BessieReorderDrop.tabAction(payload: .tab(id: "t1", workspaceID: "w1"), over: "t2", workspaceID: "w1", projection: projection), .tabMove(id: "t1", insertIndex: 2))
        XCTAssertNil(BessieReorderDrop.tabAction(payload: tabPayload, over: "t2", workspaceID: "w2", projection: projection))
    }

    func testSplitDragRatioUsesAxisExtentAndStaysUsable() {
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.5, translation: 100, extent: 500), 0.7, accuracy: 0.0001)
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.2, translation: -500, extent: 500), 0.1, accuracy: 0.0001)
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.8, translation: 500, extent: 500), 0.9, accuracy: 0.0001)
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.5, translation: 100, extent: 0), 0.5, accuracy: 0.0001)
    }

    func testPaneActionTargetNeverEscapesTheVisibleTab() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)
        let visible = Set(["p1"])

        XCTAssertEqual(
            BessiePaneActionTarget.resolve(selectedPaneID: "p1", visiblePaneIDs: visible, projection: projection),
            "p1"
        )
        XCTAssertEqual(
            BessiePaneActionTarget.resolve(selectedPaneID: "p3", visiblePaneIDs: visible, projection: projection),
            "p1"
        )
        XCTAssertNil(
            BessiePaneActionTarget.resolve(selectedPaneID: "p3", visiblePaneIDs: [], projection: projection)
        )
    }
}

private extension HerdrSnapshot {
    static let paneMoveFixture = HerdrSnapshot(
        version: "0.7.5", protocolVersion: 17,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p1",
        workspaces: [
            .object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("alpha"), "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(2), "active_tab_id": .string("t1"), "agent_status": .string("idle")]),
            .object(["workspace_id": .string("w2"), "number": .number(2), "label": .string("beta"), "focused": .bool(false), "pane_count": .number(1), "tab_count": .number(1), "active_tab_id": .string("t3"), "agent_status": .string("idle")]),
        ],
        tabs: [
            .object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("build"), "focused": .bool(true), "pane_count": .number(1), "agent_status": .string("idle")]),
            .object(["tab_id": .string("t2"), "workspace_id": .string("w1"), "number": .number(2), "label": .string("review"), "focused": .bool(false), "pane_count": .number(1), "agent_status": .string("idle")]),
            .object(["tab_id": .string("t3"), "workspace_id": .string("w2"), "number": .number(1), "label": .string("shell"), "focused": .bool(false), "pane_count": .number(1), "agent_status": .string("idle")]),
        ],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1)]),
            .object(["pane_id": .string("p2"), "terminal_id": .string("term2"), "workspace_id": .string("w1"), "tab_id": .string("t2"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
            .object(["pane_id": .string("p3"), "terminal_id": .string("term3"), "workspace_id": .string("w2"), "tab_id": .string("t3"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
        ],
        layouts: [], agents: []
    )

    static let surfaceFixture = HerdrSnapshot(
        version: "0.7.5", protocolVersion: 17,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p2",
        workspaces: [
            .object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("alpha"), "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(1), "active_tab_id": .string("t1"), "agent_status": .string("blocked")]),
            .object(["workspace_id": .string("w2"), "number": .number(2), "label": .string("beta"), "focused": .bool(false), "pane_count": .number(1), "tab_count": .number(1), "active_tab_id": .string("t2"), "agent_status": .string("idle")]),
        ],
        tabs: [
            .object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("build"), "focused": .bool(true), "pane_count": .number(2), "agent_status": .string("blocked")]),
            .object(["tab_id": .string("t2"), "workspace_id": .string("w2"), "number": .number(1), "label": .string("shell"), "focused": .bool(false), "pane_count": .number(1), "agent_status": .string("idle")]),
        ],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(false), "label": .string("blocked pane"), "agent": .string("codex"), "agent_status": .string("blocked"), "revision": .number(1)]),
            .object(["pane_id": .string("p2"), "terminal_id": .string("term2"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true), "label": .string("done pane"), "agent": .string("claude"), "agent_status": .string("done"), "revision": .number(2)]),
            .object(["pane_id": .string("p3"), "terminal_id": .string("term3"), "workspace_id": .string("w2"), "tab_id": .string("t2"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
        ],
        layouts: [],
        agents: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(false), "agent": .string("codex"), "name": .string("Codex one"), "agent_status": .string("idle"), "revision": .number(3)]),
            .object(["pane_id": .string("p3"), "terminal_id": .string("term3"), "workspace_id": .string("w2"), "tab_id": .string("t2"), "focused": .bool(false), "display_agent": .string("Claude"), "name": .string("Claude two"), "agent_status": .string("unknown"), "revision": .number(4)]),
        ]
    )
}
