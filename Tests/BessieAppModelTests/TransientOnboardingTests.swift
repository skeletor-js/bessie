import Foundation
import XCTest
@testable import BessieApp
@testable import BessieCore

/// Behavior tests for the transient-onboarding contract: entering onboarding
/// owns its run, durable state is only committed after acceptance, and
/// transient onboarding progress can never destroy prior durable completion.
@MainActor
final class TransientOnboardingTests: XCTestCase {
    // MARK: - Run Setup Again must not erase durable completion before replacement success

    func testRunSetupAgainKeepsDurableCompletionUntilReplacementSetupSucceeds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        XCTAssertTrue(settings.finishSetup(connected: true, hasWorkspace: true, terminalControllerReady: true))
        XCTAssertTrue(reloadedSettings(root: root).onboarding.completed)

        settings.runSetupAgain()
        settings.advanceSetup(runtimeReady: true, sessionReady: true, workspaceReady: false, terminalControllerReady: false)

        // A crash/relaunch mid re-setup must boot into the completed product,
        // not lose the prior successful onboarding.
        XCTAssertTrue(
            reloadedSettings(root: root).onboarding.completed,
            "Run Setup Again must keep the durable completion marker until the replacement setup succeeds"
        )
    }

    func testCancelSetupAgainRestoresCompletedStateOnDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        XCTAssertTrue(settings.finishSetup(connected: true, hasWorkspace: true, terminalControllerReady: true))
        settings.runSetupAgain()

        settings.cancelSetupAgainBeforeMaterialization()

        XCTAssertTrue(settings.onboarding.completed)
        XCTAssertTrue(reloadedSettings(root: root).onboarding.completed)
    }

    func testFirstOnboardingProgressNeverClaimsDurableCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        XCTAssertFalse(settings.onboarding.completed)

        settings.advanceSetup(runtimeReady: true, sessionReady: true, workspaceReady: false, terminalControllerReady: false)

        XCTAssertFalse(reloadedSettings(root: root).onboarding.completed)
    }

    // MARK: - Entering onboarding resets to a clean transient run

    func testBeginIsolatedOnboardingResetsStepAndErrorsWithoutTouchingConnections() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        XCTAssertTrue(settings.addConnection(name: "Studio", sshHost: "studio-mac", session: "work"))
        let connectionsBefore = try Data(contentsOf: root.appendingPathComponent("connections.json"))
        settings.advanceSetup(runtimeReady: true, sessionReady: true, workspaceReady: false, terminalControllerReady: false)
        XCTAssertNotEqual(settings.onboarding.step, .connect)

        settings.beginIsolatedOnboarding()

        XCTAssertEqual(settings.onboarding.step, .connect)
        XCTAssertFalse(settings.onboarding.completed)
        XCTAssertNil(settings.onboardingCompletionError)
        XCTAssertNil(settings.connectionError)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("connections.json")),
            connectionsBefore,
            "Entering onboarding must not rewrite durable connection settings"
        )
    }

    // MARK: - Completion cleanup is best-effort, never a completion blocker

    func testLaunchCleanupFailureDoesNotBlockFreshOnboarding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PendingOnboardingAttemptStore(url: root.appendingPathComponent("attempt.json"))

        let coordinator = OnboardingCompletionCoordinator(
            store: store,
            clearAttempt: { throw CocoaError(.fileWriteNoPermission) }
        )

        XCTAssertEqual(coordinator.stage, .idle, "Launch metadata cleanup is best-effort and must not fail the coordinator")
        XCTAssertNil(coordinator.error)
        XCTAssertNil(coordinator.attempt)
        XCTAssertTrue(coordinator.canSubmit)
    }

    func testCompletionAttemptCleanupFailureStillCompletesSetup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PendingOnboardingAttemptStore(url: root.appendingPathComponent("attempt.json"))
        let coordinator = OnboardingCompletionCoordinator(
            store: store,
            clearAttempt: { throw CocoaError(.fileWriteNoPermission) }
        )
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.waitingForFirstFrame, ids: ("workspace", "tab", "pane"))

        XCTAssertNoThrow(
            try coordinator.advance(.completed),
            "A pending-attempt cleanup failure must not block a successfully opened terminal"
        )
        XCTAssertEqual(coordinator.stage, .completed)
        XCTAssertNil(coordinator.attempt)
    }

    // MARK: - Acceptance isolation

    func testPendingAttemptURLHonorsAbsoluteEnvironmentOverrideOnly() {
        let overridden = OnboardingCompletionCoordinator.defaultAttemptURL(
            environment: ["BESSIE_PENDING_ONBOARDING_PATH": "/tmp/isolated/attempt.json"]
        )
        XCTAssertEqual(overridden.path, "/tmp/isolated/attempt.json")

        let relativeIgnored = OnboardingCompletionCoordinator.defaultAttemptURL(
            environment: ["BESSIE_PENDING_ONBOARDING_PATH": "relative/attempt.json"]
        )
        XCTAssertTrue(
            relativeIgnored.path.hasSuffix("Bessie/pending-onboarding-attempt.json"),
            "a non-absolute override must be ignored, got \(relativeIgnored.path)"
        )
        XCTAssertEqual(
            OnboardingCompletionCoordinator.defaultAttemptURL(environment: [:]).path,
            relativeIgnored.path
        )
    }

    // MARK: - Level-triggered completion reconciliation identity

    func testReconcileSignatureChangesWhenPaneAppearsWithSameWorkspaceCount() throws {
        let before = try HerdrSessionProjection(snapshot: Self.snapshot(paneID: "p-old"))
        let after = try HerdrSessionProjection(snapshot: Self.snapshot(paneID: "p-setup"))
        XCTAssertEqual(before.workspaces.count, after.workspaces.count)

        XCTAssertNotEqual(
            OnboardingReconciliation.signature(projection: before),
            OnboardingReconciliation.signature(projection: after),
            "the setup pane appearing must re-trigger reconciliation even when the workspace count is unchanged"
        )
        XCTAssertEqual(
            OnboardingReconciliation.signature(projection: before),
            OnboardingReconciliation.signature(projection: before)
        )
        XCTAssertEqual(OnboardingReconciliation.signature(projection: nil), "")
    }

    // MARK: - Working feedback identifies its phase

    func testProgressLabelIdentifiesEachInFlightStage() {
        let inFlight: [OnboardingCompletionStage] = [.connecting, .creatingWorkspace, .adoptingWorkspace, .waitingForFirstFrame]
        for stage in inFlight {
            XCTAssertFalse(OnboardingProgressLabel.text(for: stage).isEmpty)
        }
        XCTAssertEqual(Set(inFlight.map { OnboardingProgressLabel.text(for: $0) }).count, inFlight.count,
                       "each in-flight phase must be visibly distinguishable so a stall identifies itself")
        XCTAssertEqual(OnboardingProgressLabel.text(for: .waitingForFirstFrame), "Opening your Herdr terminal…")
    }

    // MARK: - Helpers

    private static func snapshot(paneID: String) -> HerdrSnapshot {
        HerdrSnapshot(
            version: "0.8.0", protocolVersion: 19,
            focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: paneID,
            workspaces: [.object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("work"),
                                  "focused": .bool(true), "pane_count": .number(1), "tab_count": .number(1),
                                  "active_tab_id": .string("t1"), "agent_status": .string("idle")])],
            tabs: [.object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1),
                            "label": .string("tab"), "focused": .bool(true), "pane_count": .number(1),
                            "agent_status": .string("idle")])],
            panes: [.object(["pane_id": .string(paneID), "terminal_id": .string("term1"),
                             "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true),
                             "cwd": .string("/srv/work"), "agent_status": .string("idle"), "revision": .number(1)])],
            layouts: [], agents: []
        )
    }

    // MARK: - Notification choice commits atomically with completion

    func testFinishSetupCommitsNotificationPolicyAtomicallyWithCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        XCTAssertEqual(settings.preferences.notifications, .blockedOnly)

        XCTAssertTrue(settings.finishSetup(
            connected: true, hasWorkspace: true, terminalControllerReady: true,
            notificationPolicy: .blockedAndDone
        ))

        XCTAssertEqual(settings.preferences.notifications, .blockedAndDone)
        let reloaded = reloadedSettings(root: root)
        XCTAssertTrue(reloaded.onboarding.completed)
        XCTAssertEqual(
            reloaded.preferences.notifications, .blockedAndDone,
            "The notification choice must persist in the same save as completion"
        )
    }

    func testFailedCompletionPersistenceLeavesNotificationPreferenceUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        // Make the presentation save fail: a directory occupies the file path.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("presentation.json"),
            withIntermediateDirectories: true
        )

        XCTAssertFalse(settings.finishSetup(
            connected: true, hasWorkspace: true, terminalControllerReady: true,
            notificationPolicy: .blockedAndDone
        ))

        XCTAssertFalse(settings.onboarding.completed)
        XCTAssertEqual(
            settings.preferences.notifications, .blockedOnly,
            "A completion persistence failure must not change the in-memory notification preference"
        )
        XCTAssertNotNil(settings.onboardingCompletionError)
    }

    func testFinishSetupCommitsAcceptedConnectionOnlyWithCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        let accepted = try BessieConnectionDefinition(
            id: "accepted-remote", name: "Accepted Remote", kind: .ssh,
            sshHost: "studio-mac", session: "bessie-ob-0123456789abcdef01234567",
            connectAtLaunch: false
        ).validated()

        XCTAssertFalse(settings.connections.contains(where: { $0.id == accepted.id }))
        XCTAssertTrue(settings.finishSetup(
            connected: true, hasWorkspace: true, terminalControllerReady: true,
            connection: accepted
        ))

        let reloaded = reloadedSettings(root: root)
        XCTAssertTrue(reloaded.onboarding.completed)
        XCTAssertEqual(reloaded.selectedConnectionID, accepted.id)
        XCTAssertEqual(reloaded.defaultProjectConnectionID, accepted.id)
        XCTAssertEqual(reloaded.connections.first(where: { $0.id == accepted.id }), accepted)
    }

    func testFailedCompletionPersistenceRollsBackAcceptedConnection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = makeSettings(root: root)
        XCTAssertTrue(settings.addConnection(name: "Prior", sshHost: "prior-mac", session: "prior"))
        let prior = try Data(contentsOf: root.appendingPathComponent("connections.json"))
        let accepted = try BessieConnectionDefinition(
            id: "rejected-remote", name: "Rejected Remote", kind: .ssh,
            sshHost: "studio-mac", session: "bessie-ob-fedcba9876543210fedcba98",
            connectAtLaunch: false
        ).validated()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("presentation.json"),
            withIntermediateDirectories: true
        )

        XCTAssertFalse(settings.finishSetup(
            connected: true, hasWorkspace: true, terminalControllerReady: true,
            connection: accepted
        ))

        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("connections.json")), prior)
        XCTAssertFalse(settings.connections.contains(where: { $0.id == accepted.id }))
        XCTAssertFalse(reloadedSettings(root: root).connections.contains(where: { $0.id == accepted.id }))
    }

    func testCompletionRefusesToOverwriteUnreadableConnectionConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let connectionURL = root.appendingPathComponent("connections.json")
        let original = Data("not valid connection JSON".utf8)
        try original.write(to: connectionURL)
        let settings = makeSettings(root: root)
        XCTAssertTrue(settings.connectionConfigurationLoadFailed)
        let accepted = try BessieConnectionDefinition(
            id: "must-not-persist", name: "Must Not Persist", kind: .ssh,
            sshHost: "studio-mac", session: "bessie-ob-aabbccddeeff001122334455",
            connectAtLaunch: false
        ).validated()

        XCTAssertFalse(settings.finishSetup(
            connected: true, hasWorkspace: true, terminalControllerReady: true,
            connection: accepted
        ))

        XCTAssertEqual(try Data(contentsOf: connectionURL), original)
        XCTAssertFalse(settings.onboarding.completed)
        XCTAssertNotNil(settings.onboardingCompletionError)
    }

    func testStartupRollsBackConnectionOnlyCrashFromOnboardingCommitJournal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeOnboardingTransactionFixture(root: root)
        try fixture.connectionStore.save(fixture.acceptedConnections)
        try writeOnboardingJournal(fixture.journal, to: fixture.journalURL)

        let recovered = makeSettings(root: root)

        XCTAssertFalse(recovered.onboarding.completed)
        XCTAssertEqual(try fixture.connectionStore.load(), fixture.previousConnections)
        XCTAssertEqual(try fixture.presentationStore.load(), fixture.previousPresentation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journalURL.path))
    }

    func testStartupFinalizesFullyWrittenOnboardingCommitJournal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeOnboardingTransactionFixture(root: root)
        try fixture.connectionStore.save(fixture.acceptedConnections)
        try fixture.presentationStore.save(fixture.acceptedPresentation)
        try writeOnboardingJournal(fixture.journal, to: fixture.journalURL)

        let recovered = makeSettings(root: root)

        XCTAssertTrue(recovered.onboarding.completed)
        XCTAssertEqual(try fixture.connectionStore.load(), fixture.acceptedConnections)
        XCTAssertEqual(try fixture.presentationStore.load(), fixture.acceptedPresentation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.journalURL.path))
    }

    func testMalformedOnboardingCommitJournalFailsClosedWithoutRewritingSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try makeOnboardingTransactionFixture(root: root)
        let priorConnections = try Data(contentsOf: fixture.connectionStore.url)
        let priorPresentation = try Data(contentsOf: fixture.presentationStore.url)
        try Data("not a journal".utf8).write(to: fixture.journalURL)

        let blocked = makeSettings(root: root)

        XCTAssertTrue(blocked.connectionConfigurationLoadFailed)
        XCTAssertNotNil(blocked.presentationPersistenceError)
        XCTAssertEqual(try Data(contentsOf: fixture.connectionStore.url), priorConnections)
        XCTAssertEqual(try Data(contentsOf: fixture.presentationStore.url), priorPresentation)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.journalURL.path))
    }

    // MARK: - Transient fleet never persists scope changes

    func testTransientFleetScopeChangesNeverTouchDurableScopeDefault() {
        let suite = "bessie.tests.fleet.transient-scope.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("stale-remote", forKey: "Bessie.connectionScope")
        let fleet = ConnectionFleetViewModel(defaults: defaults)
        defer { fleet.stop() }
        fleet.persistsScopePreference = false
        let remote = BessieConnectionDefinition(
            id: "onboarding-remote",
            name: "Onboarding Remote",
            kind: .ssh,
            sshHost: "127.0.0.1",
            connectAtLaunch: false
        )

        fleet.start(
            connections: [BessieConnectionDefinition.localBessie, remote],
            selectedConnectionID: BessieConnectionDefinition.localBessie.id,
            runtimeSelection: .bundled,
            bundledRuntimeURL: nil
        )
        // The stale scoped connection disappeared from the configuration, so
        // the in-memory scope resets, but the durable default must survive an
        // onboarding run that never completes.
        XCTAssertEqual(fleet.herdScope, .all)
        XCTAssertEqual(defaults.string(forKey: "Bessie.connectionScope"), "stale-remote")

        fleet.setScope(.connection(id: remote.id))
        XCTAssertEqual(
            defaults.string(forKey: "Bessie.connectionScope"), "stale-remote",
            "Scope changes during onboarding must stay in memory"
        )

        fleet.setScope(.all)
        XCTAssertEqual(defaults.string(forKey: "Bessie.connectionScope"), "stale-remote")

        // Completion restores durable scope persistence.
        fleet.persistsScopePreference = true
        fleet.setScope(.connection(id: remote.id))
        XCTAssertEqual(defaults.string(forKey: "Bessie.connectionScope"), remote.id)
    }

    private func makeSettings(root: URL) -> BessieSettingsModel {
        BessieSettingsModel(
            presentationURL: root.appendingPathComponent("presentation.json"),
            connectionsURL: root.appendingPathComponent("connections.json"),
            runtimeSelectionURL: root.appendingPathComponent("runtime.json")
        )
    }

    private func reloadedSettings(root: URL) -> BessieSettingsModel {
        makeSettings(root: root)
    }

    private struct OnboardingTransactionFixture {
        let presentationStore: BessiePresentationStore
        let connectionStore: BessieConnectionStore
        let journalURL: URL
        let previousPresentation: BessiePresentationState
        let previousConnections: BessieConnectionState
        let acceptedPresentation: BessiePresentationState
        let acceptedConnections: BessieConnectionState
        let journal: BessieOnboardingSettingsJournal
    }

    private func makeOnboardingTransactionFixture(root: URL) throws -> OnboardingTransactionFixture {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let presentationStore = BessiePresentationStore(url: root.appendingPathComponent("presentation.json"))
        let connectionStore = BessieConnectionStore(url: root.appendingPathComponent("connections.json"))
        let previousPresentation = BessiePresentationState()
        let previousConnections = BessieConnectionState()
        let acceptedConnection = try BessieConnectionDefinition(
            id: "journal-remote", name: "Journal Remote", kind: .ssh,
            sshHost: "studio-mac", session: "bessie-ob-00112233445566778899aabb",
            connectAtLaunch: false
        ).validated()
        let acceptedConnections = try BessieConnectionState.validated(
            selectedConnectionID: acceptedConnection.id,
            defaultProjectConnectionID: acceptedConnection.id,
            connections: previousConnections.connections + [acceptedConnection]
        )
        let acceptedPresentation = BessiePresentationState(
            preferences: BessiePreferences(notifications: .blockedAndDone),
            firstRealTerminalCompletionVersion: BessiePresentationState.firstRealTerminalCompletionVersion
        )
        try presentationStore.save(previousPresentation)
        try connectionStore.save(previousConnections)
        let journal = BessieOnboardingSettingsJournal(
            previousPresentationExists: true,
            previousPresentation: previousPresentation,
            previousConnectionsExists: true,
            previousConnections: previousConnections,
            acceptedPresentation: acceptedPresentation,
            acceptedConnections: acceptedConnections
        )
        return OnboardingTransactionFixture(
            presentationStore: presentationStore,
            connectionStore: connectionStore,
            journalURL: BessieOnboardingSettingsTransaction.journalURL(for: connectionStore.url),
            previousPresentation: previousPresentation,
            previousConnections: previousConnections,
            acceptedPresentation: acceptedPresentation,
            acceptedConnections: acceptedConnections,
            journal: journal
        )
    }

    private func writeOnboardingJournal(_ journal: BessieOnboardingSettingsJournal, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(journal).write(to: url, options: .atomic)
    }
}
