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
}
