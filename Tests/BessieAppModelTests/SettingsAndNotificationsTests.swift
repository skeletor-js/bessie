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

    func testWorkspaceScopePersistsThroughSettingsModelRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let presentationURL = root.appendingPathComponent("presentation.json")
        let model = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let scope = BessieWorkspaceScopePreference.allTabs(
            connectionID: "herd",
            workspaceID: "workspace"
        )

        model.recordWorkspaceScope(scope)

        let reloaded = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        XCTAssertEqual(reloaded.workspaceScopePreference, scope)
    }

    func testPanePresentationSaveFailureKeepsNewestDirtyRevisionAndRetries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let presentationURL = root.appendingPathComponent("presentation.json")
        let model = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
        let pane = BessiePaneIncarnation(connectionID: "local", paneID: "pane", terminalID: "terminal")
        XCTAssertTrue(model.setPanePinned(true, incarnation: pane))
        try FileManager.default.removeItem(at: presentationURL)
        try FileManager.default.createDirectory(at: presentationURL, withIntermediateDirectories: false)

        XCTAssertTrue(model.setPaneSnooze(.oneHour, incarnation: pane, now: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(model.presentationDirtyRevision, 2)
        XCTAssertNotNil(model.presentationPersistenceError)
        XCTAssertEqual(model.panePresentationLedger.preference(for: pane)?.pinned, true)

        try FileManager.default.removeItem(at: presentationURL)
        model.retryPresentationPersistence()
        XCTAssertNil(model.presentationDirtyRevision)
        let reloaded = try BessiePresentationStore(url: presentationURL).load(now: Date(timeIntervalSince1970: 1_800_000_001))
        XCTAssertEqual(reloaded.panePresentationRevision, 2)
        XCTAssertEqual(reloaded.panePresentationPreferences?.first?.pinned, true)
        XCTAssertEqual(reloaded.panePresentationPreferences?.first?.snooze?.provenance, .oneHour)
    }

    func testBlockedPresentationSourceAllowsSessionMutationButNeverRetryRewrite() throws {
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
        let pane = BessiePaneIncarnation(connectionID: "local", paneID: "pane", terminalID: "terminal")

        XCTAssertTrue(model.setPanePinned(true, incarnation: pane))
        XCTAssertTrue(model.panePresentationLedger.preference(for: pane)?.pinned == true)
        model.retryPresentationPersistence()
        XCTAssertEqual(try Data(contentsOf: presentationURL), original)
        XCTAssertNil(model.presentationDirtyRevision)
    }

    func testLaunchNormalizationPersistsExpiredSnoozeWithAdvancedRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let presentationURL = root.appendingPathComponent("presentation.json")
        let expired = BessiePanePresentationPreference(
            connectionID: "local",
            paneID: "pane",
            terminalID: "terminal",
            snooze: .until(Date(timeIntervalSince1970: 1), provenance: .oneHour)
        )
        try BessiePresentationStore(url: presentationURL).save(BessiePresentationState(
            panePresentationRevision: 7,
            panePresentationPreferences: [expired]
        ))

        _ = BessieSettingsModel(
            presentationURL: presentationURL,
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )

        let persisted = try BessiePresentationStore(url: presentationURL).load()
        XCTAssertEqual(persisted.panePresentationRevision, 8)
        XCTAssertNil(persisted.panePresentationPreferences)
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

    func testSnoozeCancelsQueuedNotificationBeforeCommitAndWakeDoesNotReplay() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = BessieNotificationCoordinator(delivery: delivery, refreshOnInit: false)
        coordinator.refreshAuthorization()
        for _ in 0..<50 where !coordinator.authorizationLoaded {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let connection = BessieConnectionDefinition.localBessie
        let incarnation = BessiePaneIncarnation(connectionID: connection.id, paneID: "p1", terminalID: "term-1")
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        let working = BessieNotificationPane(
            paneID: "p1", terminalID: "term-1", state: .working, revision: 1,
            identity: "Codex", location: "alpha / tab / Codex", target: target
        )
        let blocked = BessieNotificationPane(
            paneID: "p1", terminalID: "term-1", state: .blocked, revision: 2,
            identity: "Codex", location: working.location, target: target
        )

        coordinator.reconcile(connection: connection, panes: [working], policy: .blockedOnly, activePaneID: nil)
        coordinator.reconcile(connection: connection, panes: [blocked], policy: .blockedOnly, activePaneID: nil)
        coordinator.suppressImmediately(incarnation)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(delivery.requests.isEmpty)

        coordinator.reconcile(connection: connection, panes: [blocked], policy: .blockedOnly, activePaneID: nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(delivery.requests.isEmpty)
    }

    func testBlockedNotificationIsCancelledWhenPaneReturnsToWorkingBeforeCommit() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = BessieNotificationCoordinator(delivery: delivery, refreshOnInit: false)
        coordinator.refreshAuthorization()
        for _ in 0..<50 where !coordinator.authorizationLoaded {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        func pane(_ state: AgentSemanticState, revision: UInt64) -> BessieNotificationPane {
            BessieNotificationPane(
                paneID: "p1", terminalID: "term-1", state: state, revision: revision,
                identity: "Codex", location: "alpha / tab / Codex", target: target
            )
        }

        coordinator.reconcile(
            connection: connection, panes: [pane(.working, revision: 1)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [pane(.blocked, revision: 2)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [pane(.working, revision: 3)],
            policy: .blockedOnly, activePaneID: nil
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(delivery.requests.isEmpty)
    }

    func testCommittedNotificationIsRemovedWhenItsConditionClears() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        let working = notificationPane(state: .working, revision: 1, target: target)
        let blocked = notificationPane(state: .blocked, revision: 2, target: target)

        coordinator.reconcile(connection: connection, panes: [working], policy: .blockedOnly, activePaneID: nil)
        coordinator.reconcile(connection: connection, panes: [blocked], policy: .blockedOnly, activePaneID: nil)
        for _ in 0..<50 where delivery.requests.isEmpty { await Task.yield() }
        let identifier = try XCTUnwrap(delivery.requests.first?.identifier)

        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .working, revision: 3, target: target)],
            policy: .blockedOnly,
            activePaneID: nil
        )

        XCTAssertTrue(delivery.removedPendingIdentifiers.contains(identifier))
        XCTAssertTrue(delivery.removedDeliveredIdentifiers.contains(identifier))
    }

    func testInvalidationDuringInFlightAddRemovesLateNotification() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let addStarted = expectation(description: "notification add started")
        delivery.addStarted = addStarted
        delivery.suspendAdds = true
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")

        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .working, revision: 1, target: target)],
            policy: .blockedOnly,
            activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .blocked, revision: 2, target: target)],
            policy: .blockedOnly,
            activePaneID: nil
        )
        await fulfillment(of: [addStarted], timeout: 1)
        let identifier = try XCTUnwrap(delivery.requests.first?.identifier)

        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .working, revision: 3, target: target)],
            policy: .blockedOnly,
            activePaneID: nil
        )
        delivery.resumeAdds()
        for _ in 0..<50 where delivery.removedDeliveredIdentifiers.filter({ $0 == identifier }).count < 2 {
            await Task.yield()
        }

        XCTAssertGreaterThanOrEqual(delivery.removedPendingIdentifiers.filter { $0 == identifier }.count, 2)
        XCTAssertGreaterThanOrEqual(delivery.removedDeliveredIdentifiers.filter { $0 == identifier }.count, 2)
    }

    func testDisconnectedOffPolicyInvalidatesTrackedNotificationsWithoutResettingHistory() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let delegate = BessieAppDelegate()
        let connection = BessieConnectionDefinition.localBessie
        let blockedTarget = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "blocked")
        let settledTarget = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "settled")
        let working = [
            notificationPane(state: .working, revision: 1, target: blockedTarget),
            notificationPane(state: .working, revision: 1, target: settledTarget),
        ]
        let changed = [
            notificationPane(state: .blocked, revision: 2, target: blockedTarget),
            notificationPane(state: .done, revision: 2, target: settledTarget),
        ]

        coordinator.reconcile(connection: connection, panes: working, policy: .blockedAndDone, activePaneID: nil)
        coordinator.reconcile(connection: connection, panes: changed, policy: .blockedAndDone, activePaneID: nil)
        for _ in 0..<50 where delivery.requests.count < 2 { await Task.yield() }
        let identifiers = try XCTUnwrap(delivery.requests.count == 2 ? delivery.requests.map(\.identifier) : nil)

        delegate.reconcileFleetNotificationSources(
            [], activeConnectionID: connection.id, mainWindowOpen: false, policy: .off,
            snoozedIncarnations: [], notifications: coordinator
        )

        XCTAssertTrue(identifiers.allSatisfy(delivery.removedPendingIdentifiers.contains))
        XCTAssertTrue(identifiers.allSatisfy(delivery.removedDeliveredIdentifiers.contains))

        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: changed)],
            activeConnectionID: connection.id, mainWindowOpen: false, policy: .blockedAndDone,
            snoozedIncarnations: [], notifications: coordinator
        )
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(delivery.requests.count, 2, "reconnect must not replay unchanged notification states")
    }

    func testDisconnectedBlockedOnlyPolicyInvalidatesOnlySettledNotification() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let delegate = BessieAppDelegate()
        let connection = BessieConnectionDefinition.localBessie
        let blockedTarget = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "blocked")
        let settledTarget = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "settled")
        coordinator.reconcile(
            connection: connection,
            panes: [
                notificationPane(state: .working, revision: 1, target: blockedTarget),
                notificationPane(state: .working, revision: 1, target: settledTarget),
            ],
            policy: .blockedAndDone,
            activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection,
            panes: [
                notificationPane(state: .blocked, revision: 2, target: blockedTarget),
                notificationPane(state: .done, revision: 2, target: settledTarget),
            ],
            policy: .blockedAndDone,
            activePaneID: nil
        )
        for _ in 0..<50 where delivery.requests.count < 2 { await Task.yield() }
        let blocked = try XCTUnwrap(delivery.requests.first { $0.content.title.contains("needs you") })
        let settled = try XCTUnwrap(delivery.requests.first { $0.content.title.contains("is done") })

        delegate.reconcileFleetNotificationSources(
            [], activeConnectionID: connection.id, mainWindowOpen: false, policy: .blockedOnly,
            snoozedIncarnations: [], notifications: coordinator
        )

        XCTAssertFalse(delivery.removedDeliveredIdentifiers.contains(blocked.identifier))
        XCTAssertTrue(delivery.removedDeliveredIdentifiers.contains(settled.identifier))

        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: [
                notificationPane(state: .blocked, revision: 2, target: blockedTarget),
                notificationPane(state: .done, revision: 2, target: settledTarget),
            ])],
            activeConnectionID: connection.id, mainWindowOpen: false, policy: .blockedAndDone,
            snoozedIncarnations: [], notifications: coordinator
        )
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(delivery.requests.count, 2, "restoring settled policy must not replay an unchanged state")
    }

    func testQueuedNotificationIsInvalidatedWhenPaneMovesWithoutStateTransition() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = BessieNotificationCoordinator(delivery: delivery, refreshOnInit: false)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let oldTarget = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        let movedTarget = PaneOpenTarget(workspaceID: "w2", tabID: "t2", paneID: "p1")
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 1, target: oldTarget)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: oldTarget)],
            policy: .blockedOnly, activePaneID: nil
        )

        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: movedTarget)],
            policy: .blockedOnly, activePaneID: nil
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(delivery.requests.isEmpty, "a topology move must cancel rather than reroute an old transition")
    }

    func testCommittedNotificationIsInvalidatedWhenPaneMovesWithoutStateTransition() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let oldTarget = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        let movedTarget = PaneOpenTarget(workspaceID: "w2", tabID: "t2", paneID: "p1")
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 1, target: oldTarget)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: oldTarget)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<50 where delivery.requests.isEmpty { await Task.yield() }
        let identifier = try XCTUnwrap(delivery.requests.first?.identifier)

        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: movedTarget)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<10 { await Task.yield() }

        XCTAssertTrue(delivery.removedPendingIdentifiers.contains(identifier))
        XCTAssertTrue(delivery.removedDeliveredIdentifiers.contains(identifier))
        XCTAssertEqual(delivery.requests.count, 1, "a topology move must not synthesize a replacement transition")
    }

    func testQueuedNotificationIsInvalidatedWhenIdentityChangesWithoutStateTransition() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = BessieNotificationCoordinator(delivery: delivery, refreshOnInit: false)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .working, revision: 1, target: target, identity: "Codex")],
            policy: .blockedOnly,
            activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .blocked, revision: 2, target: target, identity: "Codex")],
            policy: .blockedOnly,
            activePaneID: nil
        )

        coordinator.reconcile(
            connection: connection,
            panes: [notificationPane(state: .blocked, revision: 2, target: target, identity: "Claude")],
            policy: .blockedOnly,
            activePaneID: nil
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(delivery.requests.isEmpty)
    }

    func testCommittedNotificationIsInvalidatedWhenConnectionLabelChanges() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        var connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 1, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<50 where delivery.requests.isEmpty { await Task.yield() }
        let identifier = try XCTUnwrap(delivery.requests.first?.identifier)

        connection.name = "Renamed Mac"
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )

        XCTAssertTrue(delivery.removedPendingIdentifiers.contains(identifier))
        XCTAssertTrue(delivery.removedDeliveredIdentifiers.contains(identifier))
        XCTAssertEqual(delivery.requests.count, 1)
    }

    func testSupersededLateAddFailureDoesNotPublishStaleError() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let firstAddStarted = expectation(description: "first notification add started")
        delivery.addStarted = firstAddStarted
        delivery.suspendAdds = true
        delivery.addErrors[0] = TestNotificationDeliveryError.failed
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 1, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        await fulfillment(of: [firstAddStarted], timeout: 1)

        delivery.addStarted = nil
        delivery.suspendAdds = false
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 3, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 4, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<50 where delivery.requests.count < 2 { await Task.yield() }
        delivery.resumeAdds()
        for _ in 0..<50 { await Task.yield() }

        XCTAssertNil(coordinator.operationError)
    }

    func testCurrentAddSuccessClearsEarlierDeliveryError() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        delivery.addErrors[0] = TestNotificationDeliveryError.failed
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 1, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<50 where coordinator.operationError == nil { await Task.yield() }
        XCTAssertNotNil(coordinator.operationError)

        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 3, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 4, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<50 where coordinator.operationError != nil { await Task.yield() }

        XCTAssertNil(coordinator.operationError)
    }

    func testSupersededLateAddSuccessDoesNotClearCurrentFailure() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let firstAddStarted = expectation(description: "first notification add started")
        delivery.addStarted = firstAddStarted
        delivery.suspendAdds = true
        delivery.addErrors[1] = TestNotificationDeliveryError.failed
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 1, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 2, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        await fulfillment(of: [firstAddStarted], timeout: 1)
        let staleIdentifier = delivery.requests[0].identifier

        delivery.addStarted = nil
        delivery.suspendAdds = false
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .working, revision: 3, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        coordinator.reconcile(
            connection: connection, panes: [notificationPane(state: .blocked, revision: 4, target: target)],
            policy: .blockedOnly, activePaneID: nil
        )
        for _ in 0..<50 where coordinator.operationError == nil { await Task.yield() }
        let currentError = coordinator.operationError

        delivery.resumeAdds()
        for _ in 0..<50 where delivery.removedDeliveredIdentifiers.filter({ $0 == staleIdentifier }).count < 2 {
            await Task.yield()
        }

        XCTAssertEqual(coordinator.operationError, currentError)
        XCTAssertGreaterThanOrEqual(
            delivery.removedDeliveredIdentifiers.filter { $0 == staleIdentifier }.count,
            2
        )
    }

    func testDelegateTakesOverActiveConnectionAfterMainWindowClosesWithoutDuplicate() async {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let delegate = BessieAppDelegate()
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        let working = notificationPane(state: .working, revision: 1, target: target)
        let blocked = notificationPane(state: .blocked, revision: 2, target: target)

        // Product shell owns and seeds the active connection while the window is visible.
        coordinator.reconcile(connection: connection, panes: [working], policy: .blockedOnly, activePaneID: nil)
        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: [blocked])],
            activeConnectionID: connection.id,
            mainWindowOpen: true,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )
        XCTAssertTrue(delivery.requests.isEmpty)

        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: [blocked])],
            activeConnectionID: connection.id,
            mainWindowOpen: false,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )
        for _ in 0..<50 where delivery.requests.isEmpty { await Task.yield() }
        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: [blocked])],
            activeConnectionID: connection.id,
            mainWindowOpen: true,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )

        XCTAssertEqual(delivery.requests.count, 1)
    }

    func testTransientSourceLossPreservesHistoryUntilConfiguredConnectionIsRemoved() async throws {
        let delivery = TestNotificationDelivery(status: .authorized)
        let coordinator = immediateCoordinator(delivery: delivery)
        await loadAuthorization(coordinator)
        let delegate = BessieAppDelegate()
        let connection = BessieConnectionDefinition.localBessie
        let target = PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        let working = notificationPane(state: .working, revision: 1, target: target)
        let blocked = notificationPane(state: .blocked, revision: 2, target: target)

        coordinator.retainConnections([connection.id])
        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: [working])],
            activeConnectionID: connection.id,
            mainWindowOpen: false,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )
        // Projection loss during reconnect produces no source but does not mean the
        // configured connection or its authoritative pane history was deleted.
        delegate.reconcileFleetNotificationSources(
            [],
            activeConnectionID: connection.id,
            mainWindowOpen: false,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )
        delegate.reconcileFleetNotificationSources(
            [FleetNotificationSource(connection: connection, panes: [blocked])],
            activeConnectionID: connection.id,
            mainWindowOpen: false,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )
        for _ in 0..<50 where delivery.requests.isEmpty { await Task.yield() }
        let identifier = try XCTUnwrap(delivery.requests.first?.identifier)
        let removalsBeforeTransientLoss = delivery.removedDeliveredIdentifiers.count

        delegate.reconcileFleetNotificationSources(
            [],
            activeConnectionID: connection.id,
            mainWindowOpen: false,
            policy: .blockedOnly,
            snoozedIncarnations: [],
            notifications: coordinator
        )
        XCTAssertEqual(delivery.removedDeliveredIdentifiers.count, removalsBeforeTransientLoss)

        coordinator.retainConnections([])
        XCTAssertTrue(delivery.removedPendingIdentifiers.contains(identifier))
        XCTAssertTrue(delivery.removedDeliveredIdentifiers.contains(identifier))
    }

    private func immediateCoordinator(delivery: TestNotificationDelivery) -> BessieNotificationCoordinator {
        BessieNotificationCoordinator(
            delivery: delivery,
            settingsOpener: TestSystemSettingsOpener(results: []),
            applicationBundleIdentifier: "dev.bessie.app.verify",
            refreshOnInit: false,
            deliveryDelay: {}
        )
    }

    private func loadAuthorization(_ coordinator: BessieNotificationCoordinator) async {
        coordinator.refreshAuthorization()
        for _ in 0..<50 where !coordinator.authorizationLoaded { await Task.yield() }
    }

    private func notificationPane(
        state: AgentSemanticState,
        revision: UInt64,
        target: PaneOpenTarget,
        identity: String = "Codex",
        location: String = "alpha / tab / Codex"
    ) -> BessieNotificationPane {
        BessieNotificationPane(
            paneID: target.paneID,
            terminalID: "term-1",
            state: state,
            revision: revision,
            identity: identity,
            location: location,
            target: target
        )
    }
}

@MainActor
private final class TestNotificationDelivery: BessieNotificationDelivering {
    var status: UNAuthorizationStatus
    let requestedStatus: UNAuthorizationStatus
    var requestCount = 0
    var requests: [UNNotificationRequest] = []
    var removedPendingIdentifiers: [String] = []
    var removedDeliveredIdentifiers: [String] = []
    var addStarted: XCTestExpectation?
    var suspendAdds = false
    var addErrors: [Int: Error] = [:]
    private var addOrdinal = 0
    private var addContinuations: [CheckedContinuation<Void, Never>] = []

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
        let ordinal = addOrdinal
        addOrdinal += 1
        requests.append(request)
        addStarted?.fulfill()
        if suspendAdds {
            await withCheckedContinuation { continuation in
                addContinuations.append(continuation)
            }
        }
        if let error = addErrors[ordinal] {
            throw error
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(contentsOf: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }

    func resumeAdds() {
        suspendAdds = false
        let continuations = addContinuations
        addContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private enum TestNotificationDeliveryError: LocalizedError {
    case failed

    var errorDescription: String? { "delivery failed" }
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
