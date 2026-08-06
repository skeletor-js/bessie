import Foundation
import XCTest
@testable import BessieCore

final class ProjectionActionTests: XCTestCase {
    func testV1FeatureFlagsDefaultOffAndDeveloperEnvironmentOverrideIsTyped() {
        let defaults = BessieFeatureFlags.v1
        XCTAssertFalse(defaults.isEnabled(.fileBrowserEditor))
        XCTAssertFalse(defaults.isEnabled(.followFiles))

        let override = BessieFeatureFlags(environment: [
            BessieFeatureFlags.developerEnvironmentKey: "followFiles, fileBrowserEditor,unknown"
        ])
        XCTAssertTrue(override.isEnabled(.fileBrowserEditor))
        XCTAssertTrue(override.isEnabled(.followFiles))
        XCTAssertEqual(BessieFeature.allCases, [.fileBrowserEditor, .followFiles])
    }
    func testProjectionDecodesAuthoritativeFocusAndRecursiveSplitPaths() throws {
        let projection = try HerdrSessionProjection(snapshot: .projectionFixture)

        XCTAssertEqual(projection.focusedWorkspace?.id, "w1")
        XCTAssertEqual(projection.focusedTab?.id, "t1")
        XCTAssertEqual(projection.focusedPane?.id, "p2")
        guard case .split(let root) = try XCTUnwrap(projection.layouts["t1"]?.root) else {
            return XCTFail("expected split root")
        }
        XCTAssertEqual(root.path, [])
        XCTAssertEqual(root.direction, .right)
        XCTAssertEqual(root.first.paneIDs, ["p1"])
        XCTAssertEqual(root.second.paneIDs, ["p2"])
    }

    func testEveryActionUsesExactPublicMethodAndPayload() {
        let cases: [(HerdrAction, String, [String: JSONValue])] = [
            (.workspaceCreate(cwd: "/tmp", label: "alpha", focus: true), "workspace.create", ["cwd": .string("/tmp"), "label": .string("alpha"), "focus": .bool(true)]),
            (.workspaceFocus(id: "w1"), "workspace.focus", ["workspace_id": .string("w1")]),
            (.workspaceRename(id: "w1", label: "renamed"), "workspace.rename", ["workspace_id": .string("w1"), "label": .string("renamed")]),
            (.workspaceMove(id: "w1", insertIndex: 2), "workspace.move", ["workspace_id": .string("w1"), "insert_index": .number(2)]),
            (.workspaceClose(id: "w1"), "workspace.close", ["workspace_id": .string("w1")]),
            (.tabCreate(workspaceID: "w1", cwd: "/tmp", label: "tests", focus: true), "tab.create", ["workspace_id": .string("w1"), "cwd": .string("/tmp"), "label": .string("tests"), "focus": .bool(true)]),
            (.tabFocus(id: "t1"), "tab.focus", ["tab_id": .string("t1")]),
            (.tabRename(id: "t1", label: "renamed"), "tab.rename", ["tab_id": .string("t1"), "label": .string("renamed")]),
            (.tabMove(id: "t1", insertIndex: 1), "tab.move", ["tab_id": .string("t1"), "insert_index": .number(1)]),
            (.tabClose(id: "t1"), "tab.close", ["tab_id": .string("t1")]),
            (.paneSplit(targetPaneID: "p1", direction: .down, ratio: 0.4, cwd: nil, focus: true), "pane.split", ["target_pane_id": .string("p1"), "direction": .string("down"), "ratio": .number(0.4), "focus": .bool(true)]),
            (.paneFocus(id: "p1"), "pane.focus", ["pane_id": .string("p1")]),
            (.paneResize(id: "p1", direction: .right, amount: 0.1), "pane.resize", ["pane_id": .string("p1"), "direction": .string("right"), "amount": .number(0.1)]),
            (.paneSwap(id: "p1", direction: .left), "pane.swap", ["pane_id": .string("p1"), "direction": .string("left")]),
            (.paneSwapExplicit(sourceID: "p1", targetID: "p2"), "pane.swap", ["source_pane_id": .string("p1"), "target_pane_id": .string("p2")]),
            (.paneMove(id: "p1", destination: .tab(tabID: "t2", targetPaneID: "p3", split: .right, ratio: 0.5), focus: true), "pane.move", ["pane_id": .string("p1"), "destination": .object(["type": .string("tab"), "tab_id": .string("t2"), "target_pane_id": .string("p3"), "split": .string("right"), "ratio": .number(0.5)]), "focus": .bool(true)]),
            (.paneMove(id: "p1", destination: .newTab(workspaceID: "w1", label: "moved"), focus: false), "pane.move", ["pane_id": .string("p1"), "destination": .object(["type": .string("new_tab"), "workspace_id": .string("w1"), "label": .string("moved")]), "focus": .bool(false)]),
            (.paneMove(id: "p1", destination: .newWorkspace(label: "space", tabLabel: "tab"), focus: true), "pane.move", ["pane_id": .string("p1"), "destination": .object(["type": .string("new_workspace"), "label": .string("space"), "tab_label": .string("tab")]), "focus": .bool(true)]),
            (.paneZoom(id: "p1", mode: .toggle), "pane.zoom", ["pane_id": .string("p1"), "mode": .string("toggle")]),
            (.paneRename(id: "p1", label: nil), "pane.rename", ["pane_id": .string("p1"), "label": .null]),
            (.paneClose(id: "p1"), "pane.close", ["pane_id": .string("p1")]),
            (.setSplitRatio(tabID: "t1", path: [false, true], ratio: 0.7), "layout.set_split_ratio", ["tab_id": .string("t1"), "path": .array([.bool(false), .bool(true)]), "ratio": .number(0.7)]),
        ]

        for (action, method, params) in cases {
            XCTAssertEqual(action.request.method, method)
            XCTAssertEqual(action.request.params, params)
        }
    }

    func testActionClientAlwaysReconcilesFromSnapshot() throws {
        let api = RecordingMutationAPI(snapshot: .projectionFixture)
        let client = HerdrActionClient(api: api)

        let result = try client.perform(.paneRename(id: "p1", label: "worker"))

        XCTAssertEqual(api.calls, ["pane.rename", "session.snapshot"])
        XCTAssertEqual(result.focusedPane?.id, "p2")
    }

    func testActionClientBatchPreservesRequestOrderAndSnapshotsOnce() throws {
        let api = RecordingMutationAPI(snapshot: .projectionFixture)
        let client = HerdrActionClient(api: api)

        _ = try client.perform([
            .workspaceFocus(id: "w1"),
            .tabFocus(id: "t1"),
            .paneFocus(id: "p2"),
        ])

        XCTAssertEqual(api.calls, ["workspace.focus", "tab.focus", "pane.focus", "session.snapshot"])
    }

    func testCloseConfirmationAndFallbackComeFromAuthoritativeProjection() throws {
        let projection = try HerdrSessionProjection(snapshot: .projectionFixture)
        let confirmation = projection.confirmationForClosingWorkspace(id: "w1")

        XCTAssertTrue(confirmation.isRequired)
        XCTAssertTrue(confirmation.message.contains("stop processes in 2 panes"))
        XCTAssertTrue(projection.confirmationForClosingTab(id: "t1").cascadesToWorkspaceClose)
        XCTAssertTrue(projection.confirmationForClosingPane(id: "p1").message.contains("stop the pane's process"))
        XCTAssertEqual(projection.focusFallback(preferredWorkspaceID: "missing").workspaceID, "w1")
        XCTAssertEqual(projection.focusFallback(preferredWorkspaceID: "w1").paneID, "p2")
    }

    func testPrunedNavigationActionsSkipAlreadyFocusedTargets() throws {
        let projection = try HerdrSessionProjection(snapshot: .projectionFixture)
        // Fixture focus is w1/t1/p2.
        XCTAssertEqual(
            projection.prunedNavigationActions([
                .workspaceFocus(id: "w1"),
                .tabFocus(id: "t1"),
                .paneFocus(id: "p2"),
            ]),
            []
        )
        XCTAssertEqual(
            projection.prunedNavigationActions([
                .workspaceFocus(id: "w1"),
                .tabFocus(id: "t1"),
                .paneFocus(id: "p1"),
            ]),
            [.paneFocus(id: "p1")]
        )
    }

    func testApplyingLocalFocusRewritesFocusFlagsWithoutInventingEntities() throws {
        let projection = try HerdrSessionProjection(snapshot: .projectionFixture)
        let focused = try projection.applyingLocalFocus(paneID: "p1")

        XCTAssertEqual(focused.focusedPane?.id, "p1")
        XCTAssertEqual(focused.focusedTab?.id, "t1")
        XCTAssertEqual(focused.focusedWorkspace?.id, "w1")
        XCTAssertEqual(focused.panes.first { $0.id == "p1" }?.focused, true)
        XCTAssertEqual(focused.panes.first { $0.id == "p2" }?.focused, false)
        XCTAssertEqual(Set(focused.panes.map(\.id)), Set(projection.panes.map(\.id)))
    }
}

private final class RecordingMutationAPI: HerdrMutationAPI, @unchecked Sendable {
    var calls: [String] = []
    let snapshotValue: HerdrSnapshot
    init(snapshot: HerdrSnapshot) { snapshotValue = snapshot }
    func request(method: String, params: [String: JSONValue]) throws -> JSONValue { calls.append(method); return .object([:]) }
    func snapshot() throws -> HerdrSnapshot { calls.append("session.snapshot"); return snapshotValue }
}

private extension HerdrSnapshot {
    static let projectionFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p2",
        workspaces: [.object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("main"), "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(1), "active_tab_id": .string("t1"), "agent_status": .string("idle")])],
        tabs: [.object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("shell"), "focused": .bool(true), "pane_count": .number(2), "agent_status": .string("idle")])],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
            .object(["pane_id": .string("p2"), "terminal_id": .string("term2"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true), "agent_status": .string("working"), "revision": .number(2)]),
        ],
        layouts: [.object([
            "workspace_id": .string("w1"), "tab_id": .string("t1"), "zoomed": .bool(false), "focused_pane_id": .string("p2"),
            "area": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)]),
            "panes": .array([
                .object(["pane_id": .string("p1"), "focused": .bool(false), "rect": .object(["x": .number(0), "y": .number(0), "width": .number(49), "height": .number(40)])]),
                .object(["pane_id": .string("p2"), "focused": .bool(true), "rect": .object(["x": .number(51), "y": .number(0), "width": .number(49), "height": .number(40)])]),
            ]),
            "splits": .array([.object(["id": .string("split_0_root"), "direction": .string("right"), "ratio": .number(0.5), "rect": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)])])]),
        ])], agents: []
    )
}
