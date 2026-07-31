import Foundation
import XCTest
@testable import BessieCore

final class PersistenceReconnectTests: XCTestCase {
    func testReconnectPolicyIsBounded() {
        let policy = ReconnectPolicy(delays: [0.25, 0.5, 1.0])

        XCTAssertEqual(policy.delay(afterFailure: 0), 0.25)
        XCTAssertEqual(policy.delay(afterFailure: 2), 1.0)
        XCTAssertNil(policy.delay(afterFailure: 3))
    }

    func testPresentationPersistenceContainsOnlyPreferencesAndWorkspaceHint() throws {
        let state = BessiePresentationState(
            lastWorkspaceID: "workspace-hint",
            preferences: BessiePreferences(terminalFontSize: 14, paneGap: 7)
        )
        let encoded = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(Set(object.keys), ["last_workspace_id", "preferences"])
        XCTAssertNil(object["snapshot"])
        XCTAssertNil(object["workspaces"])
        XCTAssertEqual(try JSONDecoder().decode(BessiePresentationState.self, from: encoded), state)
    }

    func testConnectionStatesRepresentEveryApprovedRecoverySurface() {
        let runtime = HerdrRuntime(url: URL(fileURLWithPath: "/herdr"), source: .path)
        let identity = HerdrServerIdentity(version: "0.7.4", protocolVersion: 16)

        let states: [HerdrConnectionState] = [
            .notFound,
            .stopped(runtime: runtime, socketPath: "/tmp/herdr.sock"),
            .incompatible(runtime: runtime, identity: identity, reason: "protocol 16 is unsupported"),
            .connecting(runtime: runtime),
            .connected(runtime: runtime, socketPath: "/tmp/herdr.sock", snapshot: .fixture),
            .retrying(runtime: runtime, attempt: 2, delay: 0.5, reason: "socket closed"),
            .lost(runtime: runtime, reason: "retry budget exhausted"),
        ]

        XCTAssertEqual(states.map(\.label), ["Herdr not found", "Herdr stopped", "Herdr incompatible", "Connecting", "Connected", "Retrying", "Connection lost"])
    }

    func testCanceledConnectionRunnerStopsBeforeDiscovery() async {
        let runner = HerdrConnectionRunner(repositoryRoot: URL(fileURLWithPath: "/unused"))
        let states = ConnectionStateRecorder()
        runner.cancel()

        await runner.run { states.append($0) }

        XCTAssertTrue(states.values.isEmpty)
    }
}

private final class ConnectionStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HerdrConnectionState] = []
    var values: [HerdrConnectionState] { lock.withLock { storage } }
    func append(_ state: HerdrConnectionState) { lock.withLock { storage.append(state) } }
}

private extension HerdrSnapshot {
    static let fixture = HerdrSnapshot(
        version: "0.7.5",
        protocolVersion: 17,
        focusedWorkspaceID: nil,
        focusedTabID: nil,
        focusedPaneID: nil,
        workspaces: [], tabs: [], panes: [], layouts: [], agents: []
    )
}
