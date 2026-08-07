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
        XCTAssertEqual(state.defaultProjectConnectionID, "hermes-vps")
        XCTAssertEqual(state.connections.last?.sshHost, "hermes")
        XCTAssertTrue(state.connections.allSatisfy(\.enabled))
        XCTAssertTrue(state.connections[0].connectAtLaunch)
        XCTAssertFalse(state.connections[1].connectAtLaunch)
    }

    func testDisabledCanonicalLocalRoundTripsWithoutLosingLaunchPreference() throws {
        let remote = BessieConnectionDefinition(
            id: "hermes-vps",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes",
            enabled: true,
            connectAtLaunch: true
        )
        let local = BessieConnectionDefinition(
            id: BessieConnectionDefinition.localBessie.id,
            name: "This Mac",
            kind: .local,
            session: BessieCompatibility.sessionName,
            enabled: false,
            connectAtLaunch: false
        )
        let state = try BessieConnectionState.validated(
            selectedConnectionID: remote.id,
            defaultProjectConnectionID: remote.id,
            connections: [local, remote]
        )

        let decoded = try JSONDecoder().decode(
            BessieConnectionState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertEqual(decoded.connections.map(\.id), [local.id, remote.id])
        XCTAssertFalse(decoded.connections[0].enabled)
        XCTAssertFalse(decoded.connections[0].connectAtLaunch)
        XCTAssertEqual(decoded.selectedConnectionID, remote.id)
        XCTAssertEqual(decoded.defaultProjectConnectionID, remote.id)
    }

    func testStateRepairsSelectedAndDefaultWhenTheirConnectionIsDisabledOrRemoved() throws {
        var local = BessieConnectionDefinition.localBessie
        let remote = BessieConnectionDefinition(
            id: "hermes-vps",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes",
            enabled: true
        )
        local.enabled = false

        let disabled = try BessieConnectionState.validated(
            selectedConnectionID: local.id,
            defaultProjectConnectionID: local.id,
            connections: [local, remote]
        )
        XCTAssertEqual(disabled.selectedConnectionID, remote.id)
        XCTAssertEqual(disabled.defaultProjectConnectionID, remote.id)

        let removed = try BessieConnectionState.validated(
            selectedConnectionID: remote.id,
            defaultProjectConnectionID: remote.id,
            connections: [.localBessie]
        )
        XCTAssertEqual(removed.selectedConnectionID, BessieConnectionDefinition.localBessie.id)
        XCTAssertEqual(removed.defaultProjectConnectionID, BessieConnectionDefinition.localBessie.id)
    }

    func testStatePreservesRolesWhenDisablingOrReenablingAnotherConnection() throws {
        var local = BessieConnectionDefinition.localBessie
        let remote = BessieConnectionDefinition(
            id: "hermes-vps",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes"
        )
        local.enabled = false
        local.connectAtLaunch = false
        let disabled = try BessieConnectionState.validated(
            selectedConnectionID: remote.id,
            defaultProjectConnectionID: remote.id,
            connections: [local, remote]
        )

        local.enabled = true
        let reenabled = try BessieConnectionState.validated(
            selectedConnectionID: disabled.selectedConnectionID,
            defaultProjectConnectionID: disabled.defaultProjectConnectionID,
            connections: [local, remote]
        )

        XCTAssertEqual(reenabled.selectedConnectionID, remote.id)
        XCTAssertEqual(reenabled.defaultProjectConnectionID, remote.id)
        XCTAssertTrue(reenabled.connections[0].enabled)
        XCTAssertFalse(reenabled.connections[0].connectAtLaunch)
    }

    func testStateRejectsAConfigurationWithoutAnEnabledHerd() {
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false

        XCTAssertThrowsError(try BessieConnectionState.validated(
            selectedConnectionID: local.id,
            defaultProjectConnectionID: local.id,
            connections: [local]
        )) { error in
            XCTAssertEqual(error as? BessieConnectionStateError, .finalEnabledConnectionRequired)
        }
    }

    func testMalformedFakeLocalDoesNotOverrideCanonicalLocalAvailability() throws {
        let fakeLocal = BessieConnectionDefinition(
            id: BessieConnectionDefinition.localBessie.id,
            name: "Fake",
            kind: .ssh,
            sshHost: "other",
            enabled: false
        )
        let remoteA = BessieConnectionDefinition(id: "remote", name: "A", kind: .ssh, sshHost: "hermes")
        let remoteB = BessieConnectionDefinition(id: "remote", name: "B", kind: .ssh, sshHost: "other")

        let state = try BessieConnectionState.validated(
            selectedConnectionID: "remote",
            defaultProjectConnectionID: "remote",
            connections: [fakeLocal, remoteA, remoteB]
        )

        XCTAssertEqual(state.connections.map(\.id), ["local-bessie", "remote"])
        XCTAssertEqual(state.connections.first, .localBessie)
        XCTAssertTrue(state.connections.first?.enabled == true)
        XCTAssertEqual(state.connections.last?.name, "A")
    }

    func testConnectAtLaunchDefaultsAndRoundTrip() throws {
        let remote = try BessieConnectionDefinition(
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes",
            connectAtLaunch: true
        ).validated()
        XCTAssertTrue(BessieConnectionDefinition.localBessie.connectAtLaunch)
        XCTAssertFalse(BessieConnectionDefinition(name: "R", kind: .ssh, sshHost: "h").connectAtLaunch)

        let state = BessieConnectionState(
            selectedConnectionID: remote.id,
            connections: [
                BessieConnectionDefinition(
                    id: BessieConnectionDefinition.localBessie.id,
                    name: "This Mac",
                    kind: .local,
                    session: BessieCompatibility.sessionName,
                    connectAtLaunch: false
                ),
                remote,
            ]
        )
        XCTAssertFalse(state.connections[0].connectAtLaunch)
        XCTAssertTrue(state.connections[1].connectAtLaunch)

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(BessieConnectionState.self, from: encoded)
        XCTAssertFalse(decoded.connections[0].connectAtLaunch)
        XCTAssertTrue(decoded.connections[1].connectAtLaunch)
    }

    func testStartupConnectionsPreferExplicitLaunchSet() throws {
        let remote = BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "hermes",
            connectAtLaunch: true
        )
        let localOff = BessieConnectionDefinition(
            id: BessieConnectionDefinition.localBessie.id,
            name: "This Mac",
            kind: .local,
            connectAtLaunch: false
        )
        let startup = BessieLaunchConnections.startupConnections(
            connections: [localOff, remote],
            selectedConnectionID: localOff.id
        )
        XCTAssertEqual(startup.map(\.id), [remote.id])
        XCTAssertEqual(
            BessieLaunchConnections.preferredActiveConnectionID(
                startupConnections: startup,
                selectedConnectionID: localOff.id
            ),
            remote.id
        )
    }

    func testStartupConnectionsDoNotStartOnDemandSelectedHerd() {
        let remote = BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "hermes",
            connectAtLaunch: false
        )
        let localOff = BessieConnectionDefinition(
            id: BessieConnectionDefinition.localBessie.id,
            name: "This Mac",
            kind: .local,
            connectAtLaunch: false
        )
        let startup = BessieLaunchConnections.startupConnections(
            connections: [localOff, remote],
            selectedConnectionID: remote.id
        )
        XCTAssertTrue(startup.isEmpty)
    }

    func testStartupConnectionsExcludeDisabledHerdsEvenWhenLaunchEnabled() {
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "hermes",
            connectAtLaunch: true
        )

        let startup = BessieLaunchConnections.startupConnections(
            connections: [local, remote],
            selectedConnectionID: remote.id
        )

        XCTAssertEqual(startup.map(\.id), [remote.id])
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
        XCTAssertThrowsError(try BessieConnectionDefinition(
            name: "Bad",
            kind: .ssh,
            sshHost: "-V"
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

    func testConnectionHealthMapsConnectedLocalPresentation() {
        let presentation = ConnectPresentation(
            title: "Connected to Herdr",
            detail: "2 workspaces · 3 tabs · 4 panes",
            status: .connected
        )

        let health = ConnectionHealth(connection: .localBessie, presentation: presentation)

        XCTAssertEqual(health.connectionID, "local-bessie")
        XCTAssertEqual(health.phase, "Connected to Herdr")
        XCTAssertTrue(health.isUsable)
        XCTAssertEqual(health.detail, "2 workspaces · 3 tabs · 4 panes")
        XCTAssertTrue(health.supportsWorkspaceFS)
    }

    func testConnectionHealthMapsReconnectAndErrorPresentationsAsUnusable() {
        let connection = BessieConnectionDefinition(
            id: "remote-hermes",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes"
        )
        let reconnecting = ConnectionHealth(
            connection: connection,
            presentation: ConnectPresentation(
                title: "Reconnecting to Herdr",
                detail: "Trying again in 2 seconds.",
                status: .retrying
            )
        )
        let failed = ConnectionHealth(
            connection: connection,
            presentation: ConnectPresentation(
                title: "Couldn't reconnect",
                detail: "Your work is still running.",
                status: .lost
            )
        )

        XCTAssertEqual(reconnecting.phase, "Reconnecting to Herdr")
        XCTAssertFalse(reconnecting.isUsable)
        XCTAssertFalse(reconnecting.canRetry)
        XCTAssertEqual(failed.phase, "Couldn't reconnect")
        XCTAssertFalse(failed.isUsable)
        XCTAssertTrue(failed.canRetry)
    }

    func testConnectionHealthLimitsWorkspaceFilesystemToLocalV1() {
        let remote = BessieConnectionDefinition(
            id: "remote-hermes",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes"
        )
        let connected = ConnectPresentation(title: "Connected to Herdr", detail: "Ready", status: .connected)

        XCTAssertTrue(ConnectionHealth(connection: .localBessie, presentation: connected).supportsWorkspaceFS)
        XCTAssertFalse(ConnectionHealth(connection: remote, presentation: connected).supportsWorkspaceFS)
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
        XCTAssertTrue(plan.sshArguments.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(plan.sshArguments.contains("ControlMaster=auto"))
        XCTAssertTrue(plan.sshArguments.contains("ControlPersist=\(RemoteHerdrBridgePlan.controlPersistSeconds)"))
        XCTAssertTrue(plan.sshArguments.contains("/tmp/bessie/hermes/herdr.sock:/home/hermes/.config/herdr/herdr.sock"))
        XCTAssertTrue(plan.sshArguments.contains("/tmp/bessie/hermes/herdr-client.sock:/home/hermes/.config/herdr/herdr-client.sock"))
        XCTAssertEqual(plan.sshArguments.suffix(2), ["-N", "hermes"])
    }

    func testRemoteBridgeStartupOnlyRequestsRemoteStatus() throws {
        let connection = try BessieConnectionDefinition(
            id: "remote-hermes",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes",
            session: "bessie"
        ).validated()

        XCTAssertEqual(RemoteHerdrBridgePlan.remoteStatusCommand(for: connection), "herdr --session bessie status --json")
        XCTAssertEqual(
            RemoteHerdrBridgePlan.remoteStatusArguments(for: connection),
            ["-o", "StrictHostKeyChecking=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "hermes", "herdr --session bessie status --json"]
        )
        XCTAssertEqual(
            RemoteHerdrBridgePlan.remoteStatusArguments(for: connection, controlPath: "/tmp/bessie/ctrl.sock"),
            [
                "-o", "StrictHostKeyChecking=yes",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=8",
                "-o", "ControlMaster=auto",
                "-o", "ControlPersist=\(RemoteHerdrBridgePlan.controlPersistSeconds)",
                "-o", "ControlPath=/tmp/bessie/ctrl.sock",
                "hermes",
                "herdr --session bessie status --json",
            ]
        )
        XCTAssertFalse(RemoteHerdrBridgePlan.remoteStatusArguments(for: connection).contains { $0.contains("herdr stop") })
    }

    func testEverySSHArgumentPlanOverridesUnsafeUserHostKeyConfiguration() throws {
        let connection = BessieConnectionDefinition(
            id: "remote-example",
            name: "Example",
            kind: .ssh,
            sshHost: "example.test"
        )
        let plan = try RemoteHerdrBridgePlan(
            connection: connection,
            localDirectory: URL(fileURLWithPath: "/tmp/bessie/example"),
            remoteSocketPath: "/tmp/herdr.sock"
        )

        XCTAssertEqual(SSHHostKeyPolicy.requiredArguments, ["-o", "StrictHostKeyChecking=yes"])
        XCTAssertTrue(plan.sshArguments.starts(with: SSHHostKeyPolicy.requiredArguments))
        XCTAssertTrue(RemoteHerdrBridgePlan.remoteStatusArguments(for: connection).starts(with: SSHHostKeyPolicy.requiredArguments))
        XCTAssertTrue(SSHRemoteFileAccess(
            host: "example.test",
            controlPath: "/tmp/control.sock",
            sshExecutablePath: "/usr/bin/ssh"
        ).commandArguments.starts(with: SSHHostKeyPolicy.requiredArguments))
    }

    func testMigrationRemoteAccessRequiresExistingMuxAndCannotFallBackDirectly() {
        let arguments = SSHRemoteFileAccess(
            host: "hermes",
            controlPath: "/tmp/owned-control.sock",
            requireControlMaster: true
        ).commandArguments

        XCTAssertTrue(arguments.contains("ControlMaster=no"))
        XCTAssertTrue(arguments.contains("ProxyCommand=/usr/bin/false"))
        XCTAssertEqual(arguments.last, "hermes")
    }

    func testConfigurationLeaseBlocksMigrationAndAppStartupAcrossTheActiveMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connectionsURL = root.appendingPathComponent("connections.json")

        var appLease: BessieConfigurationLease? = try BessieConfigurationLease.acquireShared(for: connectionsURL)
        XCTAssertNotNil(appLease)
        XCTAssertThrowsError(try BessieConfigurationLease.acquireExclusive(for: connectionsURL))
        appLease = nil

        var migrationLease: BessieConfigurationLease? = try BessieConfigurationLease.acquireExclusive(for: connectionsURL)
        let marker = BessieConfigurationLease.activeMigrationMarkerURL(for: connectionsURL)
        try Data("{}".utf8).write(to: marker)
        migrationLease = nil
        XCTAssertThrowsError(try BessieConfigurationLease.acquireShared(for: connectionsURL)) { error in
            XCTAssertEqual(
                error as? BessieConfigurationLeaseError,
                .migrationInProgress(marker.path)
            )
        }
        try FileManager.default.removeItem(at: marker)
        migrationLease = try BessieConfigurationLease.acquireExclusive(for: connectionsURL)
        XCTAssertNotNil(migrationLease)
    }

    func testConfigurationLeaseFailsClosedForDanglingActiveMigrationMarker() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let connectionsURL = root.appendingPathComponent("connections.json")
        let marker = BessieConfigurationLease.activeMigrationMarkerURL(for: connectionsURL)
        try FileManager.default.createSymbolicLink(
            at: marker,
            withDestinationURL: root.appendingPathComponent("missing-marker-target")
        )

        XCTAssertThrowsError(try BessieConfigurationLease.acquireShared(for: connectionsURL)) { error in
            XCTAssertEqual(
                error as? BessieConfigurationLeaseError,
                .migrationInProgress(marker.path)
            )
        }
    }
}
