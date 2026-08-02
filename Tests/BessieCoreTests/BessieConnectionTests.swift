import Foundation
import XCTest
@testable import BessieCore

final class BessieConnectionTests: XCTestCase {
    func testConnectionStateDeduplicatesIDsAndKeepsCanonicalLocalConnection() {
        let duplicateA = BessieConnectionDefinition(id: "remote", name: "A", kind: .ssh, sshHost: "hermes")
        let duplicateB = BessieConnectionDefinition(id: "remote", name: "B", kind: .ssh, sshHost: "other")
        let fakeLocal = BessieConnectionDefinition(id: "local-bessie", name: "Fake", kind: .ssh, sshHost: "other")

        let state = BessieConnectionState(connections: [fakeLocal, duplicateA, duplicateB])

        XCTAssertEqual(state.connections.map(\.id), ["local-bessie", "remote"])
        XCTAssertEqual(state.connections.first, .localBessie)
        XCTAssertEqual(state.connections.last?.name, "A")
    }

    func testConnectionStateDecodesAHandWrittenConfiguration() throws {
        let data = Data(#"{"selected_connection_id":"hermes-vps","connections":[{"id":"local-bessie","name":"This Mac","kind":"local","session":"bessie"},{"id":"hermes-vps","name":"Hermes VPS","kind":"ssh","ssh_host":"hermes"}]}"#.utf8)

        let state = try JSONDecoder().decode(BessieConnectionState.self, from: data)

        XCTAssertEqual(state.selectedConnectionID, "hermes-vps")
        XCTAssertEqual(state.connections.last?.sshHost, "hermes")
    }

    func testConnectionStateKeepsLocalAndRemoteSessionsSelectable() throws {
        let remote = try BessieConnectionDefinition(
            id: "remote-hermes",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes",
            session: nil
        ).validated()
        let state = BessieConnectionState(selectedConnectionID: remote.id, connections: [remote])

        XCTAssertEqual(state.connections.map(\.id), [BessieConnectionDefinition.localBessie.id, remote.id])
        XCTAssertEqual(state.selectedConnectionID, remote.id)
        XCTAssertEqual(state.connections[1].detail, "SSH · hermes · default")
    }

    func testConnectionValidationRejectsShellSyntax() {
        XCTAssertThrowsError(try BessieConnectionDefinition(
            name: "Bad",
            kind: .ssh,
            sshHost: "hermes; open -a Calculator"
        ).validated())
        XCTAssertThrowsError(try BessieConnectionDefinition(
            name: "Bad",
            kind: .ssh,
            sshHost: "hermes",
            session: "default && nope"
        ).validated())
    }

    func testConnectionStorePersistsSelectionWithoutCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BessieConnectionStore(url: directory.appendingPathComponent("connections.json"))
        let remote = BessieConnectionDefinition(name: "Hermes VPS", kind: .ssh, sshHost: "hermes")
        let state = BessieConnectionState(selectedConnectionID: remote.id, connections: [.localBessie, remote])

        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("private_key"))
    }

    func testRemoteBridgeForwardsBothPublicHerdrSocketsPrivately() throws {
        let connection = BessieConnectionDefinition(
            id: "remote-hermes",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes"
        )
        let plan = try RemoteHerdrBridgePlan(
            connection: connection,
            localDirectory: URL(fileURLWithPath: "/tmp/bessie/hermes"),
            remoteSocketPath: "/home/hermes/.config/herdr/herdr.sock"
        )

        XCTAssertEqual(plan.localSocketPath, "/tmp/bessie/hermes/herdr.sock")
        XCTAssertEqual(plan.localClientSocketPath, "/tmp/bessie/hermes/herdr-client.sock")
        XCTAssertEqual(plan.remoteClientSocketPath, "/home/hermes/.config/herdr/herdr-client.sock")
        XCTAssertTrue(plan.sshArguments.contains("StreamLocalBindUnlink=yes"))
        XCTAssertTrue(plan.sshArguments.contains("/tmp/bessie/hermes/herdr.sock:/home/hermes/.config/herdr/herdr.sock"))
        XCTAssertTrue(plan.sshArguments.contains("/tmp/bessie/hermes/herdr-client.sock:/home/hermes/.config/herdr/herdr-client.sock"))
        XCTAssertEqual(plan.sshArguments.suffix(2), ["-N", "hermes"])
    }
}
