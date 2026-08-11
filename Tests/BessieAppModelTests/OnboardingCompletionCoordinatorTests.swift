import XCTest
@testable import BessieApp
@testable import BessieCore

@MainActor
final class OnboardingCompletionCoordinatorTests: XCTestCase {
    func testSubmitSerializesDuplicateFinalActionsAndPersistsAuthoritativeIDs() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = RecordingOnboardingMaterializationService()
        let coordinator = OnboardingCompletionCoordinator(store: fixture.store, service: service)

        coordinator.submit(connectionID: "local", path: "/tmp/bessie-onboarding")
        coordinator.submit(connectionID: "local", path: "/tmp/bessie-onboarding")
        await waitUntil { coordinator.stage == .waitingForFirstFrame }

        XCTAssertEqual(service.calls, 1)
        XCTAssertEqual(service.progressStages, [.connecting, .creatingWorkspace])
        XCTAssertEqual(coordinator.attempt?.connectionID, "fresh-connection")
        XCTAssertEqual(coordinator.attempt?.workspaceID, "workspace-1")
        XCTAssertEqual(coordinator.attempt?.tabID, "tab-1")
        XCTAssertEqual(coordinator.attempt?.paneID, "pane-1")
        XCTAssertEqual(try fixture.store.load(), coordinator.attempt)

        try coordinator.advance(.completed)
        XCTAssertNil(coordinator.attempt)
        XCTAssertNil(try fixture.store.load())
    }

    func testRelaunchResumesTheSamePendingAttempt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = OnboardingCompletionCoordinator(store: fixture.store)
        let attempt = try first.begin(connectionID: "remote", path: "/srv/project")
        try first.advance(.connecting)

        let resumed = OnboardingCompletionCoordinator(store: fixture.store)

        XCTAssertEqual(resumed.attempt?.attemptID, attempt.attemptID)
        XCTAssertEqual(resumed.stage, .connecting)
        XCTAssertEqual(try resumed.begin(connectionID: "other", path: "/other").attemptID, attempt.attemptID)
    }

    func testRelaunchMigratesLegacyLongOnboardingSessionToFreshBoundedAttempt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy = try PendingOnboardingAttempt(
            attemptID: "bessie-legacy-attempt",
            connectionID: "legacy-remote",
            sessionName: "bessie-onboarding-2025118d-daff-4541-958e-deaff5eb527f",
            path: "/srv/project",
            stage: .failed,
            workspaceID: "old-workspace",
            tabID: "old-tab",
            paneID: "old-pane"
        )
        try fixture.store.save(legacy)

        let resumed = OnboardingCompletionCoordinator(store: fixture.store)
        let migrated = try XCTUnwrap(resumed.attempt)

        XCTAssertNotEqual(migrated.attemptID, legacy.attemptID)
        XCTAssertEqual(migrated.connectionID, legacy.connectionID)
        XCTAssertEqual(migrated.path, legacy.path)
        XCTAssertTrue(migrated.sessionName.hasPrefix("bessie-ob-"))
        XCTAssertEqual(migrated.sessionName.utf8.count, 34)
        XCTAssertEqual(migrated.stage, .validating)
        XCTAssertNil(migrated.workspaceID)
        XCTAssertNil(migrated.tabID)
        XCTAssertNil(migrated.paneID)
        XCTAssertEqual(try fixture.store.load(), migrated)
    }

    func testCancellationClearsOnlyPreMaterializationAttempt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(store: fixture.store)
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.cancelBeforeMaterialization()
        XCTAssertNil(try fixture.store.load())

        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.startingSession)
        try coordinator.cancelBeforeMaterialization()
        XCTAssertNotNil(try fixture.store.load())
    }

    func testCompletionCleanupFailureKeepsThePriorAttemptResumable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(
            store: fixture.store,
            clearAttempt: { throw CocoaError(.fileWriteNoPermission) }
        )
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.waitingForFirstFrame, ids: ("workspace", "tab", "pane"))
        let prior = try XCTUnwrap(coordinator.attempt)

        XCTAssertThrowsError(try coordinator.advance(.completed))

        XCTAssertEqual(coordinator.stage, .waitingForFirstFrame)
        XCTAssertEqual(coordinator.attempt, prior)
        XCTAssertEqual(try fixture.store.load(), prior)
        XCTAssertNotNil(coordinator.error)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for onboarding completion state")
    }
}

@MainActor
private final class RecordingOnboardingMaterializationService: OnboardingMaterializationService {
    var calls = 0
    var progressStages: [OnboardingCompletionStage] = []

    func materialize(
        _ attempt: PendingOnboardingAttempt,
        progress: (OnboardingCompletionStage) throws -> Void
    ) async throws -> OnboardingMaterializationResult {
        calls += 1
        for stage in [OnboardingCompletionStage.connecting, .creatingWorkspace] {
            progressStages.append(stage)
            try progress(stage)
        }
        return OnboardingMaterializationResult(
            connectionID: "fresh-connection",
            workspaceID: "workspace-1",
            tabID: "tab-1",
            paneID: "pane-1"
        )
    }
}

private struct Fixture {
    let root: URL
    let store: PendingOnboardingAttemptStore

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = PendingOnboardingAttemptStore(url: root.appendingPathComponent("attempt.json"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
