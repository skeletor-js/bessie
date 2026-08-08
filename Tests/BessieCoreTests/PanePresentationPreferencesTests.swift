import Darwin
import Foundation
import XCTest
@testable import BessieCore

final class PanePresentationPreferencesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testTaggedSnoozeRoundTripsAndRejectsMalformedTimedValue() throws {
        let snooze = BessiePaneSnooze.until(
            now.addingTimeInterval(3_600),
            provenance: .oneHour
        )
        let encoded = try JSONEncoder().encode(snooze)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["kind"] as? String, "until")
        XCTAssertEqual(object["provenance"] as? String, "oneHour")
        XCTAssertNotNil(object["wake_at"])
        XCTAssertEqual(try JSONDecoder().decode(BessiePaneSnooze.self, from: encoded), snooze)
        XCTAssertThrowsError(try JSONDecoder().decode(
            BessiePaneSnooze.self,
            from: Data(#"{"kind":"until","provenance":"oneHour"}"#.utf8)
        ))
    }

    func testLedgerNormalizesDefaultsDuplicatesExpiredAndIncarnationMismatch() throws {
        let old = BessiePanePresentationPreference(
            connectionID: "local",
            paneID: "pane",
            terminalID: "terminal-old",
            pinned: true
        )
        let current = BessiePanePresentationPreference(
            connectionID: "local",
            paneID: "pane",
            terminalID: "terminal-current",
            pinned: false,
            snooze: .until(now.addingTimeInterval(60), provenance: .oneHour)
        )
        let replacement = BessiePanePresentationPreference(
            connectionID: "local",
            paneID: "pane",
            terminalID: "terminal-current",
            pinned: true,
            snooze: .until(now.addingTimeInterval(-1), provenance: .oneHour)
        )
        let defaultRecord = BessiePanePresentationPreference(
            connectionID: "local",
            paneID: "default",
            terminalID: "terminal-default"
        )

        let ledger = try BessiePanePresentationLedger(
            revision: 7,
            records: [old, current, replacement, defaultRecord],
            now: now
        )

        XCTAssertEqual(ledger.revision, 7)
        XCTAssertEqual(ledger.records, [replacement.withSnooze(nil), old])
        XCTAssertNil(ledger.preference(for: .init(
            connectionID: "local",
            paneID: "pane",
            terminalID: "different"
        )))
    }

    func testPinAndSnoozeMutationsAreIndependentAndMonotonic() throws {
        let identity = BessiePaneIncarnation(connectionID: "local", paneID: "pane", terminalID: "terminal")
        var ledger = try BessiePanePresentationLedger(now: now)

        XCTAssertTrue(try ledger.setPinned(true, for: identity))
        XCTAssertEqual(ledger.revision, 1)
        XCTAssertFalse(try ledger.setPinned(true, for: identity))
        XCTAssertEqual(ledger.revision, 1)
        XCTAssertTrue(try ledger.setSnooze(.indefinite, for: identity, now: now))
        XCTAssertEqual(ledger.revision, 2)
        XCTAssertTrue(try ledger.setPinned(false, for: identity))
        XCTAssertEqual(ledger.preference(for: identity)?.snooze, .indefinite)
        XCTAssertTrue(try ledger.wake(identity, now: now))
        XCTAssertEqual(ledger.revision, 4)
        XCTAssertNil(ledger.preference(for: identity))
    }

    func testEveryPresetUsesOneActionTimeAndTomorrowUsesNextLocalNineAM() throws {
        XCTAssertNil(BessiePaneSnoozePreset.untilFurtherNotice.deadline(now: now))
        XCTAssertEqual(BessiePaneSnoozePreset.thirtyMinutes.deadline(now: now), now.addingTimeInterval(1_800))
        XCTAssertEqual(BessiePaneSnoozePreset.oneHour.deadline(now: now), now.addingTimeInterval(3_600))
        XCTAssertEqual(BessiePaneSnoozePreset.threeHours.deadline(now: now), now.addingTimeInterval(10_800))
        XCTAssertEqual(BessiePaneSnoozePreset.twelveHours.deadline(now: now), now.addingTimeInterval(43_200))
        XCTAssertEqual(BessiePaneSnoozePreset.twentyFourHours.deadline(now: now), now.addingTimeInterval(86_400))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        let action = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 22, minute: 15)))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8, hour: 9)))
        XCTAssertEqual(BessiePaneSnoozePreset.tomorrow.deadline(now: action, calendar: calendar), expected)
    }

    func testSnoozeScheduleUsesNearestDeadlineAndOnlyRunsWatchdogWhenTimed() throws {
        let soon = BessiePanePresentationPreference(
            connectionID: "local", paneID: "soon", terminalID: "t1",
            snooze: .until(now.addingTimeInterval(20), provenance: .thirtyMinutes)
        )
        let later = BessiePanePresentationPreference(
            connectionID: "local", paneID: "later", terminalID: "t2",
            snooze: .until(now.addingTimeInterval(80), provenance: .oneHour)
        )
        let indefinite = BessiePanePresentationPreference(
            connectionID: "local", paneID: "indefinite", terminalID: "t3",
            snooze: .indefinite
        )

        XCTAssertEqual(BessiePaneSnoozeSchedule(records: [later, indefinite, soon], now: now).nextDeadline, now.addingTimeInterval(20))
        XCTAssertTrue(BessiePaneSnoozeSchedule(records: [later], now: now).needsWatchdog)
        XCTAssertFalse(BessiePaneSnoozeSchedule(records: [indefinite], now: now).needsWatchdog)
        XCTAssertNil(BessiePaneSnoozeSchedule(records: [soon], now: now.addingTimeInterval(30)).nextDeadline)
    }

    func testPresentationStoreBoundsAndRestrictiveModes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Bessie/presentation.json")
        let store = BessiePresentationStore(url: url)
        let record = BessiePanePresentationPreference(
            connectionID: "local",
            paneID: "pane",
            terminalID: "terminal",
            pinned: true
        )
        try store.save(BessiePresentationState(
            panePresentationRevision: 1,
            panePresentationPreferences: [record]
        ))

        XCTAssertEqual(try store.load(now: now).panePresentationPreferences, [record])
        let directoryMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
        ).intValue
        let fileMode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(directoryMode & 0o077, 0)
        XCTAssertEqual(fileMode & 0o077, 0)

        try Data(repeating: 0, count: BessiePresentationStore.maximumFileBytes + 1).write(to: url)
        XCTAssertThrowsError(try store.load(now: now)) { error in
            XCTAssertEqual(error as? BessiePresentationPersistenceError, .fileTooLarge)
        }
    }

    func testWorkspaceScopePreferenceRoundTripsWithoutBreakingLegacyPresentationFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("presentation.json")
        let store = BessiePresentationStore(url: url)
        let scopes: [BessieWorkspaceScopePreference] = [
            .selectedTab(connectionID: "herd", workspaceID: "workspace", tabID: "tab"),
            .allTabs(connectionID: "herd", workspaceID: "workspace"),
            .allWorkspaces(connectionID: "herd"),
            .allHerds,
        ]

        for scope in scopes {
            try store.save(BessiePresentationState(workspaceScope: scope))
            XCTAssertEqual(try store.load().workspaceScope, scope)
        }

        let legacy = Data(#"{"schemaVersion":1,"state":{"preferences":{}}}"#.utf8)
        try legacy.write(to: url)
        XCTAssertNil(try store.load().workspaceScope)
    }

    func testPresentationLeaseIsExclusive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("presentation.json")
        var first: BessiePresentationLease? = try BessiePresentationLease.acquire(for: url)
        XCTAssertNotNil(first)
        let descriptor = open(BessiePresentationLease.lockURL(for: url).path, O_RDWR | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertNotEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        first = nil
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        flock(descriptor, LOCK_UN)
        XCTAssertNoThrow(try BessiePresentationLease.acquire(for: url))
    }
}

private extension BessiePanePresentationPreference {
    func withSnooze(_ snooze: BessiePaneSnooze?) -> Self {
        var copy = self
        copy.snooze = snooze
        return copy
    }
}
