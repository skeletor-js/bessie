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

    func testRelaunchDiscardsPendingAttemptInsteadOfApplyingPriorOnboardingState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = OnboardingCompletionCoordinator(store: fixture.store)
        _ = try first.begin(connectionID: "remote", path: "/srv/project")
        try first.advance(.connecting)

        let fresh = OnboardingCompletionCoordinator(store: fixture.store)

        XCTAssertNil(fresh.attempt)
        XCTAssertEqual(fresh.stage, .idle)
        XCTAssertNil(try fixture.store.load())
    }

    func testFailedRunResubmitCreatesFreshAttemptWithCurrentChoices() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(store: fixture.store, service: FailingOnboardingMaterializationService())

        coordinator.submit(connectionID: "stale-remote", path: "/srv/stale")
        await waitUntil { coordinator.stage == .failed }
        let failed = try XCTUnwrap(coordinator.attempt)

        let retried = try coordinator.begin(connectionID: "fresh-remote", path: "/srv/fresh")

        XCTAssertEqual(retried.connectionID, "fresh-remote", "A failed run must not leak its connection into the next run")
        XCTAssertEqual(retried.path, "/srv/fresh", "A failed run must not leak its path into the next run")
        XCTAssertNotEqual(retried.attemptID, failed.attemptID)
        XCTAssertNotEqual(retried.sessionName, failed.sessionName, "A retry must own a fresh session name")
        XCTAssertNil(retried.workspaceID)
        XCTAssertNil(retried.tabID)
        XCTAssertNil(retried.paneID)
    }

    func testCompletionPersistenceFailureKeepsAttemptRetryableAndStopsWorking() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(store: fixture.store)
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.waitingForFirstFrame, ids: ("workspace", "tab", "pane"))
        XCTAssertTrue(coordinator.isWorking)

        XCTAssertFalse(coordinator.completeAfterTerminalFocus(persistCompletion: { false }))

        XCTAssertEqual(coordinator.stage, .waitingForFirstFrame, "the coordinator must not commit completion before durable persistence")
        XCTAssertNotNil(coordinator.attempt, "the materialized attempt must survive a persistence failure for retry")
        XCTAssertTrue(coordinator.canSubmit)
        XCTAssertNotNil(coordinator.error, "the failure must surface; onboarding must never spin silently")
        XCTAssertFalse(coordinator.isWorking, "a surfaced error must end the working presentation")

        XCTAssertTrue(coordinator.completeAfterTerminalFocus(persistCompletion: { true }))
        XCTAssertEqual(coordinator.stage, .completed)
        XCTAssertNil(coordinator.attempt)
    }

    func testFocusFailureSurfacesErrorAndRetryResumesWorking() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(store: fixture.store)
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.waitingForFirstFrame, ids: ("workspace", "tab", "pane"))

        coordinator.reportCompletionFailure("Bessie couldn't focus the ready terminal. Try Finish again.")

        XCTAssertFalse(coordinator.isWorking)
        XCTAssertNotNil(coordinator.error)
        XCTAssertEqual(coordinator.stage, .waitingForFirstFrame)
        XCTAssertTrue(coordinator.canSubmit, "Finish must stay available for a completion retry")

        coordinator.retryCompletion()

        XCTAssertNil(coordinator.error)
        XCTAssertTrue(coordinator.isWorking, "retrying completion must visibly resume the working state")
        XCTAssertEqual(coordinator.attempt?.paneID, "pane", "retry must reuse the materialized attempt, not re-bootstrap")
    }

    func testBeginFreshRunAfterCompletedRunAllowsNewSubmission() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(store: fixture.store)
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.waitingForFirstFrame, ids: ("workspace", "tab", "pane"))
        XCTAssertTrue(coordinator.completeAfterTerminalFocus(persistCompletion: { true }))
        XCTAssertEqual(coordinator.stage, .completed)
        XCTAssertFalse(coordinator.canSubmit, "a completed coordinator must not accept a submission until a fresh run begins")

        coordinator.beginFreshRun()

        XCTAssertEqual(coordinator.stage, .idle)
        XCTAssertNil(coordinator.attempt)
        XCTAssertNil(coordinator.error)
        XCTAssertTrue(coordinator.canSubmit, "Run Setup Again must be able to submit a new run after prior success")
        let fresh = try coordinator.begin(connectionID: "second-remote", path: "/srv/fresh")
        XCTAssertEqual(fresh.connectionID, "second-remote")
        XCTAssertEqual(coordinator.stage, .validating, "a fresh run must begin a brand-new attempt")
    }

    func testBeginFreshRunSurvivesMetadataCleanupFailure() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let coordinator = OnboardingCompletionCoordinator(
            store: fixture.store,
            clearAttempt: { throw CocoaError(.fileWriteNoPermission) }
        )
        _ = try coordinator.begin(connectionID: "local", path: "/tmp/project")
        try coordinator.advance(.waitingForFirstFrame, ids: ("workspace", "tab", "pane"))
        XCTAssertTrue(coordinator.completeAfterTerminalFocus(persistCompletion: { true }))

        coordinator.beginFreshRun()

        XCTAssertEqual(coordinator.stage, .idle, "metadata cleanup is best-effort; the in-memory reset must always happen")
        XCTAssertNil(coordinator.attempt)
        XCTAssertTrue(coordinator.canSubmit)
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

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for onboarding completion state")
    }
}

@MainActor
private final class FailingOnboardingMaterializationService: OnboardingMaterializationService {
    func materialize(
        _ attempt: PendingOnboardingAttempt,
        progress: (OnboardingCompletionStage) throws -> Void
    ) async throws -> OnboardingMaterializationResult {
        try progress(.connecting)
        throw OnboardingMaterializationError.connectionUnavailable("Simulated remote bootstrap failure.")
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
