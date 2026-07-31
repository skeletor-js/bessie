import Foundation
import XCTest
@testable import BessieCore

final class SurfaceProjectionTests: XCTestCase {
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
    }

    func testPreferencesRoundTripEveryApprovedV1SettingAndDecodeLegacyValues() throws {
        let preferences = BessiePreferences(
            appearance: .light,
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
        let events = planner.events(for: [blockedAgain, doneAgain], policy: .blockedAndDone, activePaneID: "p2")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Claude needs you")
        XCTAssertEqual(events.first?.body, "alpha / build / Claude")
        XCTAssertEqual(events.first?.target, blocked.target)
        XCTAssertEqual(planner.events(for: [blockedAgain, doneAgain], policy: .blockedAndDone, activePaneID: nil), [])
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
        layouts: [], agents: []
    )
}
