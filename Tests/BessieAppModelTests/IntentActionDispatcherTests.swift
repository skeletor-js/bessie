import XCTest
@testable import BessieApp
@testable import BessieCore

final class IntentActionDispatcherTests: XCTestCase {
    func testRegisteredPilotActionsMapToIntentRequests() {
        XCTAssertEqual(
            BessiePilotIntentMapping.request(for: .paneFocus(id: "p1"), connectionID: "c1")?.intent,
            BessieIntentID("pane.focus")
        )
        XCTAssertEqual(
            BessiePilotIntentMapping.request(for: .workspaceFocus(id: "w1"), connectionID: "c1")?.params,
            ["connection_id": .string("c1"), "workspace_id": .string("w1")]
        )
        XCTAssertEqual(
            BessiePilotIntentMapping.request(for: .workspaceClose(id: "w1"), connectionID: "c1")?.intent,
            BessieIntentID("workspace.close")
        )
    }

    func testNonPilotActionsAreNotIntercepted() {
        XCTAssertNil(BessiePilotIntentMapping.request(for: .tabFocus(id: "t1"), connectionID: "c1"))
        XCTAssertNil(BessiePilotIntentMapping.request(
            for: .paneSplit(targetPaneID: "p1", direction: .right, ratio: 0.5, cwd: nil, focus: true),
            connectionID: "c1"
        ))
    }

    func testSharedLivePortRoutesConnectionStatusByExplicitID() {
        let live = AppIntentLivePort()
        let clientA = HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-a.sock"))
        let clientB = HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-b.sock"))
        live.update(client: clientA, connectionID: "connection-a", projection: nil)
        live.update(client: clientB, connectionID: "connection-b", projection: nil)
        let dispatcher = BessieIntentActionDispatcher(live: live, projects: BessieProjectStore(
            rootURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        ))

        let second = dispatcher.execute(BessieIntentRequest(
            id: "second", intent: "connection.status", params: ["connection_id": .string("connection-b")]
        ))
        let missing = dispatcher.execute(BessieIntentRequest(
            id: "missing", intent: "connection.status", params: ["connection_id": .string("connection-c")]
        ))

        XCTAssertEqual(second.value?["connected"], .bool(true))
        XCTAssertEqual(missing.value?["connected"], .bool(false))
    }

    func testInstallProjectionDoesNotRequireClientReconnect() throws {
        let live = AppIntentLivePort()
        let snapshot = HerdrSnapshot(
            version: "0.8.0",
            protocolVersion: 19,
            focusedWorkspaceID: "w1",
            focusedTabID: "t1",
            focusedPaneID: "p2",
            workspaces: [
                .object([
                    "workspace_id": .string("w1"), "number": .number(1), "label": .string("alpha"),
                    "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(1),
                    "active_tab_id": .string("t1"), "agent_status": .string("idle"),
                ]),
            ],
            tabs: [
                .object([
                    "tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1),
                    "label": .string("build"), "focused": .bool(true), "pane_count": .number(2),
                    "agent_status": .string("idle"),
                ]),
            ],
            panes: [
                .object([
                    "pane_id": .string("p1"), "terminal_id": .string("term1"),
                    "workspace_id": .string("w1"), "tab_id": .string("t1"),
                    "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1),
                ]),
                .object([
                    "pane_id": .string("p2"), "terminal_id": .string("term2"),
                    "workspace_id": .string("w1"), "tab_id": .string("t1"),
                    "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1),
                ]),
            ],
            layouts: [
                .object([
                    "workspace_id": .string("w1"), "tab_id": .string("t1"), "zoomed": .bool(false),
                    "focused_pane_id": .string("p2"),
                    "area": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)]),
                    "panes": .array([
                        .object([
                            "pane_id": .string("p1"), "focused": .bool(false),
                            "rect": .object(["x": .number(0), "y": .number(0), "width": .number(49), "height": .number(40)]),
                        ]),
                        .object([
                            "pane_id": .string("p2"), "focused": .bool(true),
                            "rect": .object(["x": .number(51), "y": .number(0), "width": .number(49), "height": .number(40)]),
                        ]),
                    ]),
                    "splits": .array([
                        .object([
                            "id": .string("split_0_root"), "direction": .string("right"), "ratio": .number(0.5),
                            "rect": .object(["x": .number(0), "y": .number(0), "width": .number(100), "height": .number(40)]),
                        ]),
                    ]),
                ]),
            ],
            agents: []
        )
        let projection = try HerdrSessionProjection(snapshot: snapshot)
        let client = HerdrActionClient(api: HerdrSocketAPI(socketPath: "/tmp/herdr-a.sock"))
        live.update(client: client, connectionID: "c1", projection: projection)

        let optimistic = try projection.applyingLocalFocus(paneID: "p1")
        live.installProjection(optimistic, connectionID: "c1")

        XCTAssertEqual(try live.projection(connectionID: "c1").focusedPane?.id, "p1")
        XCTAssertTrue(live.isConnected(connectionID: "c1"))
    }
}
