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
