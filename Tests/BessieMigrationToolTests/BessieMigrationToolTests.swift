import BessieCore
import Darwin
import Foundation
import XCTest
@testable import BessieMigrationTool

final class BessieMigrationToolTests: XCTestCase {
    func testMigrationControlPathIsDeterministicAndLeavesOpenSSHSocketSuffixHeadroom() {
        let operationID = UUID(uuidString: "72616101-7E4F-4E96-A483-3F020E009419")!
        let path = BessieProjectTargetMigration.migrationSSHControlPath(operationID: operationID)

        XCTAssertEqual(
            path,
            "/private/tmp/.bessie-migration-726161017E4F4E96A4833F020E009419-m/control.sock"
        )
        XCTAssertLessThan(path.utf8.count + 17, MemoryLayout.size(ofValue: sockaddr_un().sun_path))
    }

    func testInertPrejournalRecoveryArchivesEvidenceRemovesOnlyOwnerDirectoryAndRetainsMarker() throws {
        let fixture = try PrejournalRecoveryFixture()
        defer { fixture.remove() }
        var processInspections = 0
        var muxChecks = 0
        var sourceChecks = 0
        var journalChecks = 0

        let result = try BessieMigrationTool.archiveInertPrejournalEvidence(
            sourceDirectory: fixture.sourceDirectory,
            controlPath: fixture.controlPath,
            archiveDirectory: fixture.archiveDirectory,
            activeMarkerURL: fixture.activeMarkerURL,
            activeMarkerData: fixture.activeMarkerData,
            expectation: fixture.expectation,
            inspectProcesses: { path in
                XCTAssertEqual(path, fixture.controlPath)
                processInspections += 1
            },
            muxCheck: { path, host in
                XCTAssertEqual(path, fixture.controlPath)
                XCTAssertEqual(host, fixture.expectation.host)
                muxChecks += 1
                return 255
            },
            requireSourcesUnchanged: { sourceChecks += 1 },
            requireJournalAbsent: { journalChecks += 1 }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sourceDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.activeMarkerURL.path))
        XCTAssertEqual(try Data(contentsOf: fixture.activeMarkerURL), fixture.activeMarkerData)
        XCTAssertEqual(
            try Data(contentsOf: result.archiveDirectory.appendingPathComponent("owner.json")),
            fixture.ownerData
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.archiveDirectory.appendingPathComponent("gate.json").path))
        XCTAssertEqual(result.reportURL.lastPathComponent, "recovery.json")
        XCTAssertEqual(result.reportSHA256, BessieProjectTargetMigration.sha256(try Data(contentsOf: result.reportURL)))
        XCTAssertEqual(processInspections, 4)
        XCTAssertEqual(muxChecks, 2)
        XCTAssertEqual(sourceChecks, 3)
        XCTAssertEqual(journalChecks, 3)
    }

    func testPrejournalRecoveryRejectsPIDSocketProcessMuxAndUnknownInventoryWithoutRemovingSource() throws {
        enum Failure: CaseIterable { case pid, socket, process, mux, unknownInventory }

        for failure in Failure.allCases {
            let fixture = try PrejournalRecoveryFixture(ownerPID: failure == .pid ? 4242 : nil)
            defer { fixture.remove() }
            if failure == .socket {
                try Data().write(to: URL(fileURLWithPath: fixture.controlPath))
            }
            if failure == .unknownInventory {
                try Data("preserve".utf8).write(
                    to: fixture.sourceDirectory.appendingPathComponent("operator-evidence")
                )
            }

            XCTAssertThrowsError(try BessieMigrationTool.archiveInertPrejournalEvidence(
                sourceDirectory: fixture.sourceDirectory,
                controlPath: fixture.controlPath,
                archiveDirectory: fixture.archiveDirectory,
                activeMarkerURL: fixture.activeMarkerURL,
                activeMarkerData: fixture.activeMarkerData,
                expectation: fixture.expectation,
                inspectProcesses: { _ in
                    if failure == .process { throw FixtureFailure.expected }
                },
                muxCheck: { _, _ in failure == .mux ? 0 : 255 },
                requireSourcesUnchanged: {},
                requireJournalAbsent: {}
            ), "\(failure)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceDirectory.path), "\(failure)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.activeMarkerURL.path), "\(failure)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.archiveDirectory.path), "\(failure)")
        }
    }

    func testPrejournalRecoveryRejectsJournalOrArchiveFailureWithoutRemovingSource() throws {
        for failure in ["journal", "archive"] {
            let fixture = try PrejournalRecoveryFixture()
            defer { fixture.remove() }
            if failure == "archive" {
                try FileManager.default.createDirectory(at: fixture.archiveDirectory, withIntermediateDirectories: false)
            }

            XCTAssertThrowsError(try BessieMigrationTool.archiveInertPrejournalEvidence(
                sourceDirectory: fixture.sourceDirectory,
                controlPath: fixture.controlPath,
                archiveDirectory: fixture.archiveDirectory,
                activeMarkerURL: fixture.activeMarkerURL,
                activeMarkerData: fixture.activeMarkerData,
                expectation: fixture.expectation,
                inspectProcesses: { _ in },
                muxCheck: { _, _ in 255 },
                requireSourcesUnchanged: {},
                requireJournalAbsent: {
                    if failure == "journal" { throw FixtureFailure.expected }
                }
            ))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceDirectory.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.activeMarkerURL.path))
        }
    }

    func testPrejournalRecoveryResumesAfterGatePublicationAndAfterOwnerUnlink() throws {
        for interruption in ["gate", "unlink"] {
            let fixture = try PrejournalRecoveryFixture()
            defer { fixture.remove() }
            var didInterrupt = false

            XCTAssertThrowsError(try BessieMigrationTool.archiveInertPrejournalEvidence(
                sourceDirectory: fixture.sourceDirectory,
                controlPath: fixture.controlPath,
                archiveDirectory: fixture.archiveDirectory,
                activeMarkerURL: fixture.activeMarkerURL,
                activeMarkerData: fixture.activeMarkerData,
                expectation: fixture.expectation,
                inspectProcesses: { _ in },
                muxCheck: { _, _ in 255 },
                requireSourcesUnchanged: {},
                requireJournalAbsent: {},
                afterGatePublished: {
                    if interruption == "gate", !didInterrupt {
                        didInterrupt = true
                        throw FixtureFailure.expected
                    }
                },
                afterOwnerUnlinked: {
                    if interruption == "unlink", !didInterrupt {
                        didInterrupt = true
                        throw FixtureFailure.expected
                    }
                }
            ))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.archiveDirectory.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceDirectory.path))

            let result = try BessieMigrationTool.archiveInertPrejournalEvidence(
                sourceDirectory: fixture.sourceDirectory,
                controlPath: fixture.controlPath,
                archiveDirectory: fixture.archiveDirectory,
                activeMarkerURL: fixture.activeMarkerURL,
                activeMarkerData: fixture.activeMarkerData,
                expectation: fixture.expectation,
                inspectProcesses: { _ in },
                muxCheck: { _, _ in 255 },
                requireSourcesUnchanged: {},
                requireJournalAbsent: {}
            )
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sourceDirectory.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.reportURL.path))

            let repeated = try BessieMigrationTool.archiveInertPrejournalEvidence(
                sourceDirectory: fixture.sourceDirectory,
                controlPath: fixture.controlPath,
                archiveDirectory: fixture.archiveDirectory,
                activeMarkerURL: fixture.activeMarkerURL,
                activeMarkerData: fixture.activeMarkerData,
                expectation: fixture.expectation,
                inspectProcesses: { _ in XCTFail("terminal recovery must not inspect a removed source") },
                muxCheck: { _, _ in XCTFail("terminal recovery must not check a removed source"); return 0 },
                requireSourcesUnchanged: {},
                requireJournalAbsent: {}
            )
            XCTAssertEqual(repeated.reportSHA256, result.reportSHA256)
        }
    }

    func testPrejournalRecoveryPreservesLateArtifactInsteadOfRecursivelyDeletingIt() throws {
        let fixture = try PrejournalRecoveryFixture()
        defer { fixture.remove() }
        let lateArtifact = fixture.sourceDirectory.appendingPathComponent("late-control-socket")

        XCTAssertThrowsError(try BessieMigrationTool.archiveInertPrejournalEvidence(
            sourceDirectory: fixture.sourceDirectory,
            controlPath: fixture.controlPath,
            archiveDirectory: fixture.archiveDirectory,
            activeMarkerURL: fixture.activeMarkerURL,
            activeMarkerData: fixture.activeMarkerData,
            expectation: fixture.expectation,
            inspectProcesses: { _ in },
            muxCheck: { _, _ in 255 },
            requireSourcesUnchanged: {},
            requireJournalAbsent: {},
            afterOwnerUnlinked: {
                try Data("preserve".utf8).write(to: lateArtifact)
            }
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.sourceDirectory.path))
        XCTAssertEqual(try Data(contentsOf: lateArtifact), Data("preserve".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.archiveDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.activeMarkerURL.path))
    }

    func testExactSocketEvidenceRecoversAndPersistsMissingOwnerPID() throws {
        var owner = SSHOwnerMarker(
            operationID: UUID(),
            manifestSHA256: String(repeating: "a", count: 64),
            host: "hermes",
            token: UUID(),
            purpose: .migration,
            pid: nil
        )
        var persisted: SSHOwnerMarker?

        let pid = try BessieMigrationTool.resolveSocketOwnerPID(
            owner: &owner,
            directoryContents: Set(["owner.json", "control.sock"]),
            checkPID: { 4242 },
            persistOwner: { persisted = $0 }
        )

        XCTAssertEqual(pid, 4242)
        XCTAssertEqual(owner.pid, 4242)
        XCTAssertEqual(persisted?.pid, 4242)
        XCTAssertEqual(persisted?.operationID, owner.operationID)
        XCTAssertEqual(persisted?.manifestSHA256, owner.manifestSHA256)
    }

    func testMissingPIDIsNotRecoveredWithoutExactSocketInventory() {
        var owner = SSHOwnerMarker(
            operationID: UUID(),
            manifestSHA256: String(repeating: "b", count: 64),
            host: "hermes",
            token: UUID(),
            purpose: .verification,
            pid: nil
        )
        var checkCount = 0
        var persistCount = 0

        XCTAssertThrowsError(try BessieMigrationTool.resolveSocketOwnerPID(
            owner: &owner,
            directoryContents: Set(["owner.json"]),
            checkPID: {
                checkCount += 1
                return 4242
            },
            persistOwner: { _ in persistCount += 1 }
        ))
        XCTAssertNil(owner.pid)
        XCTAssertEqual(checkCount, 0)
        XCTAssertEqual(persistCount, 0)
    }

    func testUnknownCloseTimeArtifactIsPreservedWhenInventoryValidationFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bessie-migration-tool-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let ownerURL = directory.appendingPathComponent("owner.json")
        let unknownURL = directory.appendingPathComponent("operator-evidence")
        try Data("{}".utf8).write(to: ownerURL)
        try Data("preserve".utf8).write(to: unknownURL)

        XCTAssertThrowsError(try BessieMigrationTool.requireExactSSHDirectoryInventory(
            at: directory,
            expected: Set(["owner.json"])
        ))
        XCTAssertEqual(try Data(contentsOf: unknownURL), Data("preserve".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownerURL.path))
    }

    func testRecordedPIDMismatchRejectsMasterBeforeClose() throws {
        XCTAssertNoThrow(try BessieMigrationTool.requireMatchingMasterPID(recorded: 4242, checked: 4242))
        XCTAssertThrowsError(try BessieMigrationTool.requireMatchingMasterPID(recorded: 4242, checked: 5252)) { error in
            XCTAssertTrue(error is MigrationToolError)
        }
    }
}

private enum FixtureFailure: Error { case expected }

private final class PrejournalRecoveryFixture {
    let root: URL
    let sourceDirectory: URL
    let archiveDirectory: URL
    let activeMarkerURL: URL
    let activeMarkerData = Data("active-marker".utf8)
    let expectation: PrejournalRecoveryExpectation
    let ownerData: Data

    var controlPath: String { sourceDirectory.appendingPathComponent("control.sock").path }

    init(ownerPID: Int32? = nil) throws {
        let operationID = UUID()
        expectation = .init(
            operationID: operationID,
            manifestSHA256: String(repeating: "a", count: 64),
            host: "hermes",
            purpose: .migration
        )
        root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("bessie-prejournal-test-\(UUID().uuidString)", isDirectory: true)
        sourceDirectory = root.appendingPathComponent("owner", isDirectory: true)
        archiveDirectory = root.appendingPathComponent("archive", isDirectory: true)
        activeMarkerURL = root.appendingPathComponent("active-marker.json")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let owner = SSHOwnerMarker(
            operationID: operationID,
            manifestSHA256: expectation.manifestSHA256,
            host: expectation.host,
            token: UUID(),
            purpose: expectation.purpose,
            pid: ownerPID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        ownerData = try encoder.encode(owner)
        let ownerURL = sourceDirectory.appendingPathComponent("owner.json")
        try ownerData.write(to: ownerURL)
        try activeMarkerData.write(to: activeMarkerURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ownerURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activeMarkerURL.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
