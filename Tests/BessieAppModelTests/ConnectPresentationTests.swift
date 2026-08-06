import XCTest
@testable import BessieCore

final class ConnectPresentationTests: XCTestCase {
    func testInitialPresentationIsAnHonestConnectState() {
        let presentation = ConnectPresentation.initial

        XCTAssertEqual(presentation.title, "Connecting to Herdr")
        XCTAssertEqual(presentation.status, .notChecked)
        XCTAssertEqual(presentation.detail, "Opening your Bessie session…")
    }

    func testStartingPresentationKeepsAutomaticStartupCalmAndSpecific() {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/herdr"), source: .path)

        let presentation = ConnectPresentation(connectionState: .starting(runtime: runtime))

        XCTAssertEqual(presentation.title, "Starting Herdr")
        XCTAssertEqual(presentation.detail, "Opening your Bessie session…")
        XCTAssertEqual(presentation.status, .connecting)
    }

    func testConnectedPresentationReportsAuthoritativeSnapshotCounts() {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/herdr"), source: .path)
        let snapshot = HerdrSnapshot(
            version: "0.8.0", protocolVersion: 19,
            focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p1",
            workspaces: [.object([:])], tabs: [.object([:]), .object([:])],
            panes: [.object([:]), .object([:]), .object([:])], layouts: [], agents: []
        )

        let presentation = ConnectPresentation(connectionState: .connected(runtime: runtime, socketPath: "/tmp/herdr.sock", snapshot: snapshot))

        XCTAssertEqual(presentation.title, "Connected to Herdr")
        XCTAssertEqual(presentation.detail, "1 workspace · 2 tabs · 3 panes")
    }
}
