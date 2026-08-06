import Foundation
import XCTest
@testable import BessieCore

final class BootstrapTests: XCTestCase {
    func testAcknowledgedSubscriptionPrecedesSnapshotAndBufferedEventForcesResnapshot() throws {
        let first = HerdrSnapshot.fixture(focusedWorkspaceID: "stale")
        let converged = HerdrSnapshot.fixture(focusedWorkspaceID: "current")
        let api = RecordingHerdrAPI(
            snapshots: [first, converged],
            bufferedEvents: [HerdrEvent(name: "workspace.renamed", data: [:])]
        )

        let result = try HerdrBootstrapper().bootstrap(api: api)

        XCTAssertEqual(result.snapshot.focusedWorkspaceID, "current")
        XCTAssertEqual(api.calls, ["subscribe", "snapshot", "drain", "snapshot"])
    }

    func testNoBufferedEventsAvoidsUnnecessarySecondSnapshot() throws {
        let api = RecordingHerdrAPI(snapshots: [.fixture(focusedWorkspaceID: "current")], bufferedEvents: [])

        let result = try HerdrBootstrapper().bootstrap(api: api)

        XCTAssertEqual(result.snapshot.focusedWorkspaceID, "current")
        XCTAssertEqual(api.calls, ["subscribe", "snapshot", "drain"])
    }
}

private final class RecordingHerdrAPI: HerdrAPI, @unchecked Sendable {
    private(set) var calls: [String] = []
    private var snapshots: [HerdrSnapshot]
    private let subscription: RecordingSubscription

    init(snapshots: [HerdrSnapshot], bufferedEvents: [HerdrEvent]) {
        self.snapshots = snapshots
        subscription = RecordingSubscription(events: bufferedEvents) { }
        subscription.onDrain = { [weak self] in self?.calls.append("drain") }
    }

    func ping() throws -> HerdrServerIdentity {
        HerdrServerIdentity(version: "0.8.0", protocolVersion: 19)
    }

    func subscribe() throws -> any HerdrEventSubscription {
        calls.append("subscribe")
        return subscription
    }

    func snapshot() throws -> HerdrSnapshot {
        calls.append("snapshot")
        return snapshots.removeFirst()
    }
}

private final class RecordingSubscription: HerdrEventSubscription, @unchecked Sendable {
    private var events: [HerdrEvent]
    var onDrain: () -> Void

    init(events: [HerdrEvent], onDrain: @escaping () -> Void) {
        self.events = events
        self.onDrain = onDrain
    }

    func drainBufferedEvents() -> [HerdrEvent] {
        onDrain()
        defer { events.removeAll() }
        return events
    }

    func nextEvent() throws -> HerdrEvent? { nil }
    func close() {}
}

private extension HerdrSnapshot {
    static func fixture(focusedWorkspaceID: String?) -> HerdrSnapshot {
        HerdrSnapshot(
            version: "0.8.0",
            protocolVersion: 19,
            focusedWorkspaceID: focusedWorkspaceID,
            focusedTabID: nil,
            focusedPaneID: nil,
            workspaces: [],
            tabs: [],
            panes: [],
            layouts: [],
            agents: []
        )
    }
}
