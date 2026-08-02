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
}
