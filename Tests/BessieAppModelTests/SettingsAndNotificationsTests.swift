import Foundation
import UserNotifications
import XCTest
@testable import BessieApp
@testable import BessieCore

@MainActor
final class SettingsAndNotificationsTests: XCTestCase {
    func testCanonicalSettingsLayoutMetricsMatchBindingScreen08() {
        XCTAssertEqual(BessieSettingsLayout.maximumWidth, 780)
        XCTAssertEqual(BessieSettingsLayout.topPadding, 26)
        XCTAssertEqual(BessieSettingsLayout.horizontalPadding, 40)
        XCTAssertEqual(BessieSettingsLayout.bottomPadding, 70)
        XCTAssertEqual(BessieSettingsLayout.sectionSpacing, 30)
        XCTAssertEqual(BessieSettingsLayout.labelColumnWidth, 252)
        XCTAssertEqual(BessieSettingsLayout.columnGap, 22)
        XCTAssertEqual(BessieSettingsLayout.rowVerticalPadding, 17)
        XCTAssertEqual(BessieSettingsLayout.switchWidth, 38)
        XCTAssertEqual(BessieSettingsLayout.switchHeight, 22)
    }

    func testSettingsConnectAtLaunchPersistsPerHerd() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connectionsURL = root.appendingPathComponent("connections.json")
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertTrue(model.addConnection(name: "Hermes VPS", sshHost: "hermes", session: "bessie"))
        let remoteID = try XCTUnwrap(model.connections.first(where: { $0.kind == .ssh })?.id)
        XCTAssertFalse(model.connections.first(where: { $0.id == remoteID })?.connectAtLaunch == true)

        model.setConnectAtLaunch(connectionID: remoteID, enabled: true)
        model.setConnectAtLaunch(connectionID: BessieConnectionDefinition.localBessie.id, enabled: false)

        let reloaded = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertTrue(reloaded.connections.first(where: { $0.id == remoteID })?.connectAtLaunch == true)
        XCTAssertFalse(reloaded.connections.first(where: { $0.id == BessieConnectionDefinition.localBessie.id })?.connectAtLaunch == true)
    }

    func testSettingsDisablesSelectedLocalAndRepairsSelectedAndDefaultToRemote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connectionsURL = root.appendingPathComponent("connections.json")
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertTrue(model.addConnection(name: "Hermes VPS", sshHost: "hermes", session: "bessie"))
        let remoteID = try XCTUnwrap(model.connections.first(where: { $0.kind == .ssh })?.id)
        model.selectConnection(BessieConnectionDefinition.localBessie.id)
        model.setDefaultProjectConnection(BessieConnectionDefinition.localBessie.id)

        XCTAssertTrue(model.setConnectionEnabled(
            connectionID: BessieConnectionDefinition.localBessie.id,
            enabled: false
        ))

        XCTAssertFalse(model.connections[0].enabled)
        XCTAssertEqual(model.selectedConnectionID, remoteID)
        XCTAssertEqual(model.defaultProjectConnectionID, remoteID)
        XCTAssertEqual(try BessieConnectionStore(url: connectionsURL).load().selectedConnectionID, remoteID)
        XCTAssertEqual(try BessieConnectionStore(url: connectionsURL).load().defaultProjectConnectionID, remoteID)
    }

    func testSettingsRejectsDisablingOrRemovingFinalEnabledHerdWithoutMutation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let connectionsURL = root.appendingPathComponent("connections.json")
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        try BessieConnectionStore(url: connectionsURL).save(BessieConnectionState())
        let before = try Data(contentsOf: connectionsURL)

        XCTAssertFalse(model.setConnectionEnabled(
            connectionID: BessieConnectionDefinition.localBessie.id,
            enabled: false
        ))
        XCTAssertEqual(model.connections, [.localBessie])
        XCTAssertEqual(model.selectedConnectionID, BessieConnectionDefinition.localBessie.id)
        XCTAssertEqual(model.defaultProjectConnectionID, BessieConnectionDefinition.localBessie.id)
        XCTAssertEqual(try Data(contentsOf: connectionsURL), before)
        XCTAssertTrue(model.connectionError?.contains("at least one herd") == true)

        let remote = BessieConnectionDefinition(
            id: "remote-only",
            name: "Remote",
            kind: .ssh,
            sshHost: "hermes"
        )
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        try BessieConnectionStore(url: connectionsURL).save(try BessieConnectionState.validated(
            selectedConnectionID: remote.id,
            defaultProjectConnectionID: remote.id,
            connections: [local, remote]
        ))
        let remoteOnly = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let remoteBefore = try Data(contentsOf: connectionsURL)

        XCTAssertFalse(remoteOnly.removeConnection(remote.id))
        XCTAssertEqual(remoteOnly.connections, [local, remote])
        XCTAssertEqual(remoteOnly.selectedConnectionID, remote.id)
        XCTAssertEqual(remoteOnly.defaultProjectConnectionID, remote.id)
        XCTAssertEqual(try Data(contentsOf: connectionsURL), remoteBefore)
    }

    func testConnectionStoreWriteFailureDoesNotPublishCandidateState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let connectionsURL = root.appendingPathComponent("connections.json")
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        XCTAssertFalse(model.addConnection(name: "Hermes VPS", sshHost: "hermes", session: "bessie"))
        XCTAssertEqual(model.connections, [.localBessie])
        XCTAssertEqual(model.selectedConnectionID, BessieConnectionDefinition.localBessie.id)
        XCTAssertEqual(model.defaultProjectConnectionID, BessieConnectionDefinition.localBessie.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: connectionsURL.path))
        XCTAssertTrue(model.connectionError?.contains("couldn't save") == true)
    }

    func testUnreadableZeroEnabledConfigurationFailsClosedWithoutStartingOrRewritingLocal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let connectionsURL = root.appendingPathComponent("connections.json")
        let invalid = Data(#"{"selected_connection_id":"local-bessie","default_project_connection_id":"local-bessie","connections":[{"id":"local-bessie","name":"This Mac","kind":"local","enabled":false,"connect_at_launch":true}]}"#.utf8)
        try invalid.write(to: connectionsURL)

        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        XCTAssertTrue(model.connectionConfigurationLoadFailed)
        XCTAssertTrue(model.connections.isEmpty)
        XCTAssertTrue(model.enabledConnections.isEmpty)
        XCTAssertEqual(model.selectedConnectionID, "")
        XCTAssertFalse(model.addConnection(name: "Remote", sshHost: "hermes", session: nil))
        XCTAssertEqual(try Data(contentsOf: connectionsURL), invalid)
        XCTAssertTrue(model.connectionError?.contains("left the unreadable file untouched") == true)
    }

    func testActiveMigrationMarkerMakesSettingsFailClosedWithoutReadingOrRewritingConnections() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let connectionsURL = root.appendingPathComponent("connections.json")
        try BessieConnectionStore(url: connectionsURL).save(BessieConnectionState())
        let source = try Data(contentsOf: connectionsURL)
        try Data("{}".utf8).write(
            to: BessieConfigurationLease.activeMigrationMarkerURL(for: connectionsURL)
        )

        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: connectionsURL,
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        XCTAssertTrue(model.connectionConfigurationLoadFailed)
        XCTAssertTrue(model.connections.isEmpty)
        XCTAssertTrue(model.connectionError?.contains("migration is in progress") == true)
        XCTAssertFalse(BessieOperationalStartupPolicy.permitsOperationalSurfaces(
            connectionConfigurationLoadFailed: model.connectionConfigurationLoadFailed
        ))
        XCTAssertEqual(try Data(contentsOf: connectionsURL), source)
    }

    func testOperationalStartupPolicyAllowsNormalConfiguration() {
        XCTAssertTrue(BessieOperationalStartupPolicy.permitsOperationalSurfaces(
            connectionConfigurationLoadFailed: false
        ))
    }

    func testSettingsDefaultsAndMenuBarPreferencesPersistAndReset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let presentationURL = root.appendingPathComponent("presentation.json")
        let model = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertTrue(model.preferences.menuBarVisible)
        model.preferences.menuBarVisible = false
        model.preferences.menuBarBadgePolicy = .needsYouAndUnknown
        model.preferences.menuBarRowClickBehavior = .openBessie

        let reloaded = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertFalse(reloaded.preferences.menuBarVisible)
        XCTAssertEqual(reloaded.preferences.menuBarBadgePolicy, .needsYouAndUnknown)
        XCTAssertEqual(reloaded.preferences.menuBarRowClickBehavior, .openBessie)

        reloaded.preferences = BessiePreferences()
        XCTAssertEqual(reloaded.preferences, BessiePreferences())
    }

    func testUnknownNewerPresentationSchemaIsReportedAndNeverRewritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let presentationURL = root.appendingPathComponent("presentation.json")
        let original = Data(#"{"schemaVersion":999,"state":{"preferences":{}}}"#.utf8)
        try original.write(to: presentationURL)
        let model = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        XCTAssertNotNil(model.presentationPersistenceError)
        model.preferences.appearance = .light
        XCTAssertEqual(try Data(contentsOf: presentationURL), original)
    }

    func testFinishSetupPersistsCompletionAndReloadsCompleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let presentationURL = root.appendingPathComponent("presentation.json")
        let model = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        XCTAssertTrue(model.finishSetup(connected: true, hasWorkspace: true, terminalControllerReady: true))
        XCTAssertTrue(model.onboarding.completed)

        let reloaded = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertTrue(reloaded.onboarding.completed)
    }

    func testFinishSetupRejectsMissingRequirementsWithoutPersistingCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let presentationURL = root.appendingPathComponent("presentation.json")
        let model = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        XCTAssertFalse(model.finishSetup(connected: true, hasWorkspace: true, terminalControllerReady: false))
        XCTAssertFalse(model.onboarding.completed)
        XCTAssertNotNil(model.onboardingCompletionError)
        XCTAssertNil(try BessiePresentationStore(url: presentationURL).load().firstRealTerminalCompletionVersion)
    }

    func testTerminalReadinessDoesNotAdvanceOrCompleteOnboardingWithoutFinish() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        model.terminalBecameReady()

        XCTAssertEqual(model.onboarding.step, .connect)
        XCTAssertFalse(model.onboarding.completed)
    }

    func testFocusFailureLeavesOnboardingIncompleteAndReportsRetryableError() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        model.reportOnboardingFocusFailure()

        XCTAssertFalse(model.onboarding.completed)
        XCTAssertEqual(model.onboardingCompletionError, "Bessie couldn't focus the ready terminal. Try Finish again.")
    }

    func testRunSetupAgainCanCancelBeforeMaterializationAndRestoreCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertTrue(model.finishSetup(connected: true, hasWorkspace: true, terminalControllerReady: true))

        model.runSetupAgain()
        XCTAssertFalse(model.onboarding.completed)
        XCTAssertEqual(model.setupEntryGeneration, 1)
        model.cancelSetupAgainBeforeMaterialization()

        XCTAssertTrue(model.onboarding.completed)
        XCTAssertNotNil(try BessiePresentationStore(url: root.appendingPathComponent("presentation.json")).load().firstRealTerminalCompletionVersion)
    }

    func testSettingsPreservesExplicitAdvancedRuntimeSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtimeURL = root.appendingPathComponent("runtime.json")
        try HerdrRuntimeSelectionStore(url: runtimeURL).save(.system)

        let model = BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: runtimeURL
        )

        XCTAssertEqual(model.runtimeSelection, .system)
        XCTAssertEqual(HerdrRuntimeSelectionStore(url: runtimeURL).load(), .system)
    }

    func testTestNotificationUsesRealDeliverySeamWithDisplaySafeContentAndRoute() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = BessieNotificationCoordinator(delivery: delivery, refreshOnInit: false)
        let target = RoutedPaneTarget(connectionID: "local", workspaceID: "workspace", tabID: "tab", paneID: "pane")

        await coordinator.sendTestNotification(target: target)

        let request = try XCTUnwrap(delivery.requests.first)
        XCTAssertTrue(request.identifier.hasPrefix("bessie.test."))
        XCTAssertEqual(request.content.title, "Bessie test notification")
        XCTAssertEqual(request.content.body, "Notifications are ready. No terminal content is included.")
        XCTAssertEqual(BessieNotificationDeepLink(userInfo: request.content.userInfo)?.target, target)
        XCTAssertEqual(coordinator.testNotificationStatus, .delivered)
    }

    func testTestNotificationRequestsPermissionAndReportsDenialWithoutDelivery() async {
        let delivery = TestNotificationDelivery(status: .notDetermined, requestedStatus: .denied)
        let coordinator = BessieNotificationCoordinator(delivery: delivery, refreshOnInit: false)

        await coordinator.sendTestNotification(target: nil)

        XCTAssertEqual(delivery.requestCount, 1)
        XCTAssertTrue(delivery.requests.isEmpty)
        XCTAssertEqual(coordinator.testNotificationStatus, .denied)
    }

    func testDeniedPermissionOpensBessieNotificationSettingsThenFallsBackToGeneralNotifications() {
        let delivery = TestNotificationDelivery(status: .denied)
        let settings = TestSystemSettingsOpener(results: [false, true])
        let coordinator = BessieNotificationCoordinator(
            delivery: delivery,
            settingsOpener: settings,
            applicationBundleIdentifier: "com.skeletor.Bessie",
            refreshOnInit: false
        )

        coordinator.openNotificationSettings()

        XCTAssertEqual(settings.openedURLs.count, 2)
        XCTAssertEqual(
            settings.openedURLs[0].absoluteString,
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.skeletor.Bessie"
        )
        XCTAssertEqual(
            settings.openedURLs[1].absoluteString,
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }
}

@MainActor
private final class TestNotificationDelivery: BessieNotificationDelivering {
    var status: UNAuthorizationStatus
    let requestedStatus: UNAuthorizationStatus
    var requestCount = 0
    var requests: [UNNotificationRequest] = []

    init(status: UNAuthorizationStatus, requestedStatus: UNAuthorizationStatus = .authorized) {
        self.status = status
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws -> UNAuthorizationStatus {
        requestCount += 1
        status = requestedStatus
        return status
    }

    func add(_ request: UNNotificationRequest) async throws {
        requests.append(request)
    }
}

@MainActor
private final class TestSystemSettingsOpener: BessieSystemSettingsOpening {
    private var results: [Bool]
    var openedURLs: [URL] = []

    init(results: [Bool]) {
        self.results = results
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return results.isEmpty ? false : results.removeFirst()
    }
}
