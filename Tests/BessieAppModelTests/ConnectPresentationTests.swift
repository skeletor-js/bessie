import XCTest
@testable import BessieCore

final class ConnectPresentationTests: XCTestCase {
    func testInitialPresentationIsAnHonestConnectState() {
        let presentation = ConnectPresentation.initial

        XCTAssertEqual(presentation.title, "Connecting to Herdr")
        XCTAssertEqual(presentation.status, .notChecked)
        XCTAssertEqual(presentation.detail, "Looking for a local session…")
    }

    func testConnectedPresentationReportsAuthoritativeSnapshotCounts() {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/herdr"), source: .path)
        let snapshot = HerdrSnapshot(
            version: "0.7.5", protocolVersion: 17,
            focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p1",
            workspaces: [.object([:])], tabs: [.object([:]), .object([:])],
            panes: [.object([:]), .object([:]), .object([:])], layouts: [], agents: []
        )

        let presentation = ConnectPresentation(connectionState: .connected(runtime: runtime, socketPath: "/tmp/herdr.sock", snapshot: snapshot))

        XCTAssertEqual(presentation.title, "Connected to Herdr")
        XCTAssertEqual(presentation.detail, "1 workspace · 2 tabs · 3 panes")
    }
}
