import Darwin
import Foundation
import XCTest
@testable import BessieCore

final class BessieProjectTargetMigrationTests: XCTestCase {
    func testPreflightApplyAndAuditMigrateExactlyEighteenProjectsAndConnectionLast() throws {
        let fixture = try Fixture(projectCount: 18)
        defer { fixture.remove() }

        let preflight = try fixture.migration.preflight(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            manifestPath: fixture.manifestURL.path,
            sshControlPath: fixture.controlPath,
            sshHost: "hermes",
            sshMasterPID: 1234,
            sshOwnerToken: fixture.ownerToken
        )

        XCTAssertEqual(preflight.phase, .preflighted)
        XCTAssertEqual(preflight.projects.count, 18)
        XCTAssertEqual(try fixture.connectionState().selectedConnectionID, "hermes-vps")
        XCTAssertTrue(try fixture.connectionState().connections.first(where: { $0.id == "local-bessie" })?.enabled == true)
        let journalBeforeRepeatedPreflight = try Data(contentsOf: URL(fileURLWithPath: fixture.manifest.journalPath))
        XCTAssertThrowsError(try fixture.migration.preflight(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            manifestPath: fixture.manifestURL.path,
            sshControlPath: fixture.controlPath,
            sshHost: "hermes",
            sshMasterPID: 1234,
            sshOwnerToken: fixture.ownerToken
        )) { error in
            XCTAssertTrue(error is BessieProjectTargetMigrationError)
        }
        XCTAssertEqual(
            try Data(contentsOf: URL(fileURLWithPath: fixture.manifest.journalPath)),
            journalBeforeRepeatedPreflight
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.manifest.backupPath))

        let applied = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )
        XCTAssertEqual(applied.phase, .applied)
        XCTAssertEqual(applied.projects.filter { $0.completedResultSHA256 != nil }.count, 18)

        for (index, url) in fixture.projectURLs.enumerated() {
            let project = try BessieProjectCodec.decode(Data(contentsOf: url))
            XCTAssertEqual(project.targetConnectionID, "hermes-vps")
            XCTAssertEqual(project.folders.map(\.path), ["/srv/workstreams/project-\(index)"])
            XCTAssertEqual(project.name, "Project \(index)")
            XCTAssertEqual(project.tabs[0].name, "Work")
            XCTAssertEqual(project.tabs[0].panes.map(\.label), ["Editor", "Tests"])
            XCTAssertEqual(project.tabs[0].panes.map(\.command), ["amp", "swift test"])
        }
        let state = try fixture.connectionState()
        XCTAssertEqual(state.selectedConnectionID, "hermes-vps")
        XCTAssertEqual(state.defaultProjectConnectionID, "hermes-vps")
        XCTAssertFalse(try XCTUnwrap(state.connections.first(where: { $0.id == "local-bessie" })).enabled)
        let remote = try XCTUnwrap(state.connections.first(where: { $0.id == "hermes-vps" }))
        XCTAssertTrue(remote.enabled)
        XCTAssertTrue(remote.connectAtLaunch)

        let audited = try fixture.migration.audit(manifest: fixture.manifest, manifestData: fixture.manifestData)
        XCTAssertEqual(audited.phase, .success)
        XCTAssertEqual(audited.auditMessage, "Verified 18 migrated schema-v3 Projects and remote-only connection state.")
        XCTAssertNil(audited.sshMasterClosedAt)
        let closing = try fixture.migration.recordSSHMasterClosing(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        XCTAssertEqual(closing.phase, .closingSSHMaster)
        let closed = try fixture.migration.recordSSHMasterClosed(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        XCTAssertNotNil(closed.sshMasterClosedAt)
        XCTAssertEqual(closed.phase, .readyForRelaunch)
        XCTAssertEqual(closed.terminalOutcome, .migrated)
    }

    func testConnectionPatchPreservesUnknownFieldsAndOmittedLegacyDefaults() throws {
        let fixture = try Fixture(projectCount: 1, legacyConnectionShape: true)
        defer { fixture.remove() }

        _ = try fixture.preflight()
        _ = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.connectionURL)) as? [String: Any]
        )
        XCTAssertEqual(object["future_setting"] as? String, "preserve-me")
        XCTAssertEqual(object["selected_connection_id"] as? String, "hermes-vps")
        XCTAssertEqual(object["default_project_connection_id"] as? String, "hermes-vps")
        let definitions = try XCTUnwrap(object["connections"] as? [[String: Any]])
        let local = try XCTUnwrap(definitions.first { $0["id"] as? String == "local-bessie" })
        let remote = try XCTUnwrap(definitions.first { $0["id"] as? String == "hermes-vps" })
        XCTAssertEqual(local["future_connection_field"] as? String, "local-value")
        XCTAssertEqual(remote["future_connection_field"] as? String, "remote-value")
        XCTAssertEqual(local["enabled"] as? Bool, false)
        XCTAssertEqual(remote["enabled"] as? Bool, true)
        XCTAssertEqual(remote["connect_at_launch"] as? Bool, true)
    }

    func testPreflightRejectsMissingSymlinkNoncanonicalAndPrefixCollisionTargetsBeforeWrites() throws {
        for failure in RemoteFailure.allCases {
            let fixture = try Fixture(projectCount: 1, remoteFailure: failure)
            defer { fixture.remove() }
            let originalConnection = try Data(contentsOf: fixture.connectionURL)
            let originalProject = try Data(contentsOf: fixture.projectURLs[0])

            XCTAssertThrowsError(try fixture.migration.preflight(
                manifest: fixture.manifest,
                manifestData: fixture.manifestData,
                manifestPath: fixture.manifestURL.path,
                sshControlPath: fixture.controlPath,
                sshHost: "hermes",
                sshMasterPID: 1234,
                sshOwnerToken: fixture.ownerToken
            )) { error in
                XCTAssertTrue(error is BessieProjectTargetMigrationError, "\(failure): \(error)")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.journalPath))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.backupPath))
            XCTAssertEqual(try Data(contentsOf: fixture.connectionURL), originalConnection)
            XCTAssertEqual(try Data(contentsOf: fixture.projectURLs[0]), originalProject)
        }

        XCTAssertTrue(BessieProjectTargetMigration.containsPath(parent: "/srv/work", child: "/srv/work/project"))
        XCTAssertFalse(BessieProjectTargetMigration.containsPath(parent: "/srv/work", child: "/srv/work-old/project"))
    }

    func testPreflightRejectsHashDriftCorruptSchemaAndUnknownSourceRootBeforeBackup() throws {
        let drift = try Fixture(projectCount: 1)
        defer { drift.remove() }
        try Data("drift".utf8).append(to: drift.projectURLs[0])
        XCTAssertThrowsError(try drift.preflight())
        XCTAssertFalse(FileManager.default.fileExists(atPath: drift.manifest.backupPath))

        let corrupt = try Fixture(projectCount: 1)
        defer { corrupt.remove() }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: corrupt.projectURLs[0])) as? [String: Any])
        object["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: object).write(to: corrupt.projectURLs[0])
        XCTAssertThrowsError(try corrupt.preflight())
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.manifest.backupPath))

        let unknown = try Fixture(projectCount: 1, approvedSourceRoots: ["/different/root"])
        defer { unknown.remove() }
        XCTAssertThrowsError(try unknown.preflight())
        XCTAssertFalse(FileManager.default.fileExists(atPath: unknown.manifest.backupPath))
    }

    func testInterruptedProjectWriteRequiresResumeAndKeepsConnectionUnchangedUntilAllProjectsVerify() throws {
        let fixture = try Fixture(projectCount: 3)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        let interruption = ThrowOnce()
        let interruptedMigration = fixture.makeMigration(afterProjectWrite: { index in
            if index == 1 { try interruption.throwIfFirst() }
        })

        XCTAssertThrowsError(try interruptedMigration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        ))
        XCTAssertEqual(try BessieProjectTargetMigration.loadJournal(for: fixture.manifest).phase, .applyingProjects)
        let stillLocal = try fixture.connectionState()
        XCTAssertTrue(try XCTUnwrap(stillLocal.connections.first(where: { $0.id == "local-bessie" })).enabled)
        XCTAssertNotEqual(try BessieProjectTargetMigration.loadJournal(for: fixture.manifest).projects[1].completedResultSHA256,
                          try BessieProjectTargetMigration.loadJournal(for: fixture.manifest).projects[1].resultSHA256)

        XCTAssertThrowsError(try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        ))
        let resumed = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: true
        )
        XCTAssertEqual(resumed.phase, .applied)
        XCTAssertTrue(resumed.projects.allSatisfy { $0.completedResultSHA256 == $0.resultSHA256 })
        XCTAssertFalse(try XCTUnwrap(fixture.connectionState().connections.first(where: { $0.id == "local-bessie" })).enabled)
    }

    func testInterruptedConnectionWriteResumesOnlyFromPreparedResultHash() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        let interruption = ThrowOnce()
        let migration = fixture.makeMigration(afterConnectionWrite: { try interruption.throwIfFirst() })

        XCTAssertThrowsError(try migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        ))
        let interrupted = try BessieProjectTargetMigration.loadJournal(for: fixture.manifest)
        XCTAssertEqual(interrupted.phase, .applyingConnections)
        XCTAssertNil(interrupted.connection.completedResultSHA256)
        XCTAssertEqual(
            BessieProjectTargetMigration.sha256(try Data(contentsOf: fixture.connectionURL)),
            interrupted.connection.resultSHA256
        )

        let resumed = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: true
        )
        XCTAssertEqual(resumed.phase, .applied)
        XCTAssertEqual(resumed.connection.completedResultSHA256, resumed.connection.resultSHA256)
    }

    func testSourceDriftAfterPreflightStopsApplyWithoutChangingConnections() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        let originalConnection = try Data(contentsOf: fixture.connectionURL)
        try Data("operator edit".utf8).write(to: fixture.projectURLs[0])

        XCTAssertThrowsError(try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )) { error in
            guard case BessieProjectTargetMigrationError.sourceDrift = error else {
                return XCTFail("Expected source drift, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.connectionURL), originalConnection)
    }

    func testJournalRejectsContainedWrongBackupResultHashAndImpossibleConnectionPhase() throws {
        let wrongBackup = try Fixture(projectCount: 1)
        defer { wrongBackup.remove() }
        _ = try wrongBackup.preflight()
        try wrongBackup.mutateJournal { object in
            var projects = try XCTUnwrap(object["projects"] as? [[String: Any]])
            projects[0]["backupPath"] = URL(fileURLWithPath: wrongBackup.manifest.backupPath)
                .appendingPathComponent("manifest.json").path
            object["projects"] = projects
        }
        XCTAssertThrowsError(try wrongBackup.migration.apply(
            manifest: wrongBackup.manifest,
            manifestData: wrongBackup.manifestData,
            resume: false
        ))

        let wrongHash = try Fixture(projectCount: 1)
        defer { wrongHash.remove() }
        _ = try wrongHash.preflight()
        try wrongHash.mutateJournal { object in
            var projects = try XCTUnwrap(object["projects"] as? [[String: Any]])
            projects[0]["resultSHA256"] = String(repeating: "a", count: 64)
            object["projects"] = projects
        }
        XCTAssertThrowsError(try wrongHash.migration.apply(
            manifest: wrongHash.manifest,
            manifestData: wrongHash.manifestData,
            resume: false
        ))

        let impossiblePhase = try Fixture(projectCount: 1)
        defer { impossiblePhase.remove() }
        _ = try impossiblePhase.preflight()
        try impossiblePhase.mutateJournal { object in
            object["phase"] = "applyingConnections"
        }
        XCTAssertThrowsError(try impossiblePhase.migration.apply(
            manifest: impossiblePhase.manifest,
            manifestData: impossiblePhase.manifestData,
            resume: true
        ))
    }

    func testStructurallyForgedReadyJournalCannotPassLiveRelaunchAudit() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        try fixture.mutateJournal { object in
            var projects = try XCTUnwrap(object["projects"] as? [[String: Any]])
            for index in projects.indices {
                projects[index]["completedResultSHA256"] = projects[index]["resultSHA256"]
            }
            object["projects"] = projects
            var connection = try XCTUnwrap(object["connection"] as? [String: Any])
            connection["completedResultSHA256"] = connection["resultSHA256"]
            object["connection"] = connection
            object["phase"] = "readyForRelaunch"
            object["terminalOutcome"] = "migrated"
            object["auditMessage"] = "forged"
            object["sshMasterClosedAt"] = "2027-01-15T08:00:00Z"
        }

        XCTAssertThrowsError(try fixture.migration.verifyReadyForRelaunch(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )) { error in
            XCTAssertTrue(error is BessieProjectTargetMigrationError)
        }
        XCTAssertTrue(try fixture.connectionState().connections[0].enabled)
    }

    func testReadyJournalIsReauditedAgainstLiveStateAfterSSHClose() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        _ = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )
        _ = try fixture.migration.audit(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        _ = try fixture.migration.recordSSHMasterClosing(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        _ = try fixture.migration.recordSSHMasterClosed(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        try Data("changed-after-close".utf8).write(to: fixture.projectURLs[0])

        XCTAssertThrowsError(try fixture.migration.verifyReadyForRelaunch(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )) { error in
            XCTAssertTrue(error is BessieProjectTargetMigrationError)
        }
    }

    func testRemoteTargetDriftAfterPreflightStopsBeforeAnyProjectOrConnectionWrite() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        let availability = RemoteAvailability()
        let migration = BessieProjectTargetMigration(remoteInspector: .init { path in
            guard availability.available else {
                return .init(requestedPath: path, canonicalPath: path, exists: false, isDirectory: false, isSymbolicLink: false)
            }
            return .init(requestedPath: path, canonicalPath: path, exists: true, isDirectory: true, isSymbolicLink: false)
        })
        _ = try migration.preflight(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            manifestPath: fixture.manifestURL.path,
            sshControlPath: fixture.controlPath,
            sshHost: "hermes",
            sshMasterPID: 1234,
            sshOwnerToken: fixture.ownerToken
        )
        let sourceConnection = try Data(contentsOf: fixture.connectionURL)
        let sourceProjects = try fixture.projectURLs.map { try Data(contentsOf: $0) }
        availability.available = false

        XCTAssertThrowsError(try migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )) { error in
            guard case BessieProjectTargetMigrationError.unsafeRemotePath = error else {
                return XCTFail("Expected unsafe remote path, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: fixture.connectionURL), sourceConnection)
        XCTAssertEqual(try fixture.projectURLs.map { try Data(contentsOf: $0) }, sourceProjects)
        XCTAssertEqual(try BessieProjectTargetMigration.loadJournal(for: fixture.manifest).phase, .preflighted)
    }

    func testRemoteTargetDriftAfterAProjectWriteLeavesSourceConnectionEnabled() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        let availability = RemoteAvailability()
        let migration = BessieProjectTargetMigration(
            remoteInspector: .init { path in
                guard availability.available else {
                    return .init(requestedPath: path, canonicalPath: path, exists: false, isDirectory: false, isSymbolicLink: false)
                }
                return .init(requestedPath: path, canonicalPath: path, exists: true, isDirectory: true, isSymbolicLink: false)
            },
            afterProjectWrite: { index in
                if index == 0 { availability.available = false }
            }
        )
        _ = try migration.preflight(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            manifestPath: fixture.manifestURL.path,
            sshControlPath: fixture.controlPath,
            sshHost: "hermes",
            sshMasterPID: 1234,
            sshOwnerToken: fixture.ownerToken
        )

        XCTAssertThrowsError(try migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        ))
        let state = try fixture.connectionState()
        XCTAssertTrue(try XCTUnwrap(state.connections.first { $0.id == "local-bessie" }).enabled)
        XCTAssertEqual(state.defaultProjectConnectionID, "local-bessie")
        XCTAssertEqual(try BessieProjectTargetMigration.loadJournal(for: fixture.manifest).phase, .applyingProjects)
    }

    func testRollbackRestoresSourceBytesModesAndConnectionStateThenAuditsTerminalRollback() throws {
        let fixture = try Fixture(projectCount: 4)
        defer { fixture.remove() }
        let sourceConnection = try Data(contentsOf: fixture.connectionURL)
        let sourceProjects = try fixture.projectURLs.map { try Data(contentsOf: $0) }
        let sourceMetadata = try fixture.projectURLs.map(BessieProjectTargetMigration.metadata(at:))
        _ = try fixture.preflight()
        _ = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )

        let rolledBack = try fixture.migration.rollback(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        XCTAssertEqual(rolledBack.phase, .rolledBack)
        XCTAssertEqual(try Data(contentsOf: fixture.connectionURL), sourceConnection)
        for index in fixture.projectURLs.indices {
            XCTAssertEqual(try Data(contentsOf: fixture.projectURLs[index]), sourceProjects[index])
            XCTAssertEqual(try BessieProjectTargetMigration.metadata(at: fixture.projectURLs[index]), sourceMetadata[index])
        }
        let audit = try fixture.migration.audit(manifest: fixture.manifest, manifestData: fixture.manifestData)
        XCTAssertEqual(audit.phase, .rollbackVerified)
        XCTAssertTrue(audit.auditMessage?.contains("full byte-for-byte and metadata rollback") == true)
        XCTAssertThrowsError(try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        ))
    }

    func testRollbackPreservesMissingProjectAndRetainsVerifiedBackupForReview() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        let missingURL = fixture.projectURLs[0]
        _ = try fixture.preflight()
        _ = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )
        try FileManager.default.removeItem(at: missingURL)

        XCTAssertThrowsError(try fixture.migration.rollback(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))
        let journal = try BessieProjectTargetMigration.loadJournal(for: fixture.manifest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.projects[0].backupPath))
    }

    func testRollbackRejectsChangedBackupBytes() throws {
        let fixture = try Fixture(projectCount: 1)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        _ = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )
        let journal = try BessieProjectTargetMigration.loadJournal(for: fixture.manifest)
        try Data("changed-backup".utf8).write(to: URL(fileURLWithPath: journal.projects[0].backupPath))

        XCTAssertThrowsError(try fixture.migration.rollback(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        ))
    }

    func testRollbackAuditRejectsAndPreservesExtraProjectInventory() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        _ = try fixture.migration.apply(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            resume: false
        )
        _ = try fixture.migration.rollback(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        let extraURL = fixture.projectsURL.appendingPathComponent("extra.json")
        try Data(#"{"operator":"evidence"}"#.utf8).write(to: extraURL)

        XCTAssertThrowsError(try fixture.migration.audit(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )) { error in
            XCTAssertTrue(error is BessieProjectTargetMigrationError)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: extraURL.path))
        XCTAssertEqual(
            try BessieProjectTargetMigration.loadJournal(for: fixture.manifest).phase,
            .rolledBack
        )
    }

    func testInterruptedBackupStagingResumesOnlyWithExactOwnershipEvidence() throws {
        for step in [
            BessieMigrationBackupStep.stagingDirectoryCreated,
            .ownershipRecorded,
            .connectionCopied,
            .projectsCopied,
        ] {
            let fixture = try Fixture(projectCount: 2)
            defer { fixture.remove() }
            let interruption = ThrowOnce()
            let interrupted = fixture.makeMigration(afterBackupStep: { reached in
                if reached == step { try interruption.throwIfFirst() }
            })

            XCTAssertThrowsError(try fixture.preflight(using: interrupted), "Expected interruption at \(step)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.journalPath))
            XCTAssertEqual(try fixture.connectionState().connections[0].enabled, true)

            let recovered = try fixture.preflight()
            XCTAssertEqual(recovered.phase, .preflighted)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.manifest.backupPath))
        }
    }

    func testInterruptedBackupWithUnknownStagingEvidenceIsPreservedAndRejected() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        let interruption = ThrowOnce()
        let stagingURL = URL(fileURLWithPath: fixture.manifest.backupPath)
            .deletingLastPathComponent()
            .appendingPathComponent(".\(URL(fileURLWithPath: fixture.manifest.backupPath).lastPathComponent).staging")
        let interrupted = fixture.makeMigration(afterBackupStep: { step in
            guard step == .ownershipRecorded else { return }
            try Data("unknown-evidence".utf8).write(to: stagingURL.appendingPathComponent("future-record.json"))
            try interruption.throwIfFirst()
        })

        XCTAssertThrowsError(try fixture.preflight(using: interrupted))
        XCTAssertThrowsError(try fixture.preflight()) { error in
            XCTAssertTrue(error is BessieProjectTargetMigrationError)
        }
        XCTAssertEqual(
            try Data(contentsOf: stagingURL.appendingPathComponent("future-record.json")),
            Data("unknown-evidence".utf8)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.backupPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.journalPath))
    }

    func testInterruptedBackupWithUnsafeKnownStagingEntryIsPreservedAndRejected() throws {
        for unsafeEntry in UnsafeStagingEntry.allCases {
            let fixture = try Fixture(projectCount: 2)
            defer { fixture.remove() }
            let interruption = ThrowOnce()
            let stagingURL = URL(fileURLWithPath: fixture.manifest.backupPath)
                .deletingLastPathComponent()
                .appendingPathComponent(".\(URL(fileURLWithPath: fixture.manifest.backupPath).lastPathComponent).staging")
            let entryURL = stagingURL.appendingPathComponent("connections.json")
            let interrupted = fixture.makeMigration(afterBackupStep: { step in
                guard step == .ownershipRecorded else { return }
                switch unsafeEntry {
                case .wrongType:
                    try FileManager.default.createDirectory(at: entryURL, withIntermediateDirectories: false)
                case .danglingSymbolicLink:
                    try FileManager.default.createSymbolicLink(
                        at: entryURL,
                        withDestinationURL: stagingURL.appendingPathComponent("missing-source")
                    )
                }
                try interruption.throwIfFirst()
            })

            XCTAssertThrowsError(try fixture.preflight(using: interrupted))
            XCTAssertThrowsError(try fixture.preflight()) { error in
                XCTAssertTrue(error is BessieProjectTargetMigrationError)
            }
            var details = stat()
            XCTAssertEqual(lstat(entryURL.path, &details), 0)
            switch unsafeEntry {
            case .wrongType:
                XCTAssertEqual(details.st_mode & S_IFMT, S_IFDIR)
            case .danglingSymbolicLink:
                XCTAssertEqual(details.st_mode & S_IFMT, S_IFLNK)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.backupPath))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.manifest.journalPath))
        }
    }

    func testFailureAfterJournalPublicationRetainsRecoverableJournalAndBackupEvidence() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        let interruption = ThrowOnce()
        let interrupted = fixture.makeMigration(afterJournalWrite: {
            try interruption.throwIfFirst()
        })

        XCTAssertThrowsError(try fixture.preflight(using: interrupted))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.manifest.journalPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.manifest.backupPath))
        let journal = try fixture.migration.validateJournal(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )
        XCTAssertEqual(journal.phase, .preflighted)
        XCTAssertEqual(journal.projects.count, 2)
    }

    func testPublishedBackupTreeDigestAndExactEvidenceAreRequiredForEveryJournalRead() throws {
        let fixture = try Fixture(projectCount: 2)
        defer { fixture.remove() }
        let preflight = try fixture.preflight()
        XCTAssertEqual(preflight.schemaVersion, BessieProjectTargetMigrationJournal.currentSchemaVersion)
        XCTAssertEqual(preflight.backupTreeSHA256.count, 64)
        let unknown = URL(fileURLWithPath: fixture.manifest.backupPath)
            .appendingPathComponent("unrecognized-evidence")
        try Data("changed".utf8).write(to: unknown)

        XCTAssertThrowsError(try fixture.migration.validateJournal(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        )) { error in
            XCTAssertTrue(error is BessieProjectTargetMigrationError)
        }
        XCTAssertEqual(try Data(contentsOf: unknown), Data("changed".utf8))
    }

    func testSSHOwnershipCanRotateDurablyBeforeApply() throws {
        let fixture = try Fixture(projectCount: 1)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        let replacementToken = UUID()

        let rotated = try fixture.migration.recordSSHMasterOwnership(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData,
            sshMasterPID: 5678,
            sshOwnerToken: replacementToken
        )

        XCTAssertEqual(rotated.sshMasterPID, 5678)
        XCTAssertEqual(rotated.sshOwnerToken, replacementToken)
        let persisted = try BessieProjectTargetMigration.loadJournal(for: fixture.manifest)
        XCTAssertEqual(persisted.sshMasterPID, 5678)
        XCTAssertEqual(persisted.sshOwnerToken, replacementToken)
    }

    func testJournalRequiresExactCanonicalMigrationControlPathSpelling() throws {
        let fixture = try Fixture(projectCount: 1)
        defer { fixture.remove() }
        _ = try fixture.preflight()
        XCTAssertNoThrow(try fixture.migration.validateJournal(
            manifest: fixture.manifest,
            manifestData: fixture.manifestData
        ))
        let journalURL = URL(fileURLWithPath: fixture.manifest.journalPath)
        let original = try Data(contentsOf: journalURL)

        for invalidPath in [
            fixture.controlPath.replacingOccurrences(of: "/.bessie-migration-", with: "/./.bessie-migration-"),
            fixture.controlPath.replacingOccurrences(of: "-m/control.sock", with: "-control/control.sock"),
        ] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            object["sshControlPath"] = invalidPath
            let changed = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            let handle = try FileHandle(forWritingTo: journalURL)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: changed)
            try handle.synchronize()
            try handle.close()

            XCTAssertThrowsError(try fixture.migration.validateJournal(
                manifest: fixture.manifest,
                manifestData: fixture.manifestData
            )) { error in
                XCTAssertTrue(error is BessieProjectTargetMigrationError)
            }
        }
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}

private enum RemoteFailure: CaseIterable {
    case missing
    case symlink
    case noncanonical
    case outsideApprovedRoot
}

private enum UnsafeStagingEntry: CaseIterable {
    case wrongType
    case danglingSymbolicLink
}

private enum FixtureError: Error { case interrupted }

private final class ThrowOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var didThrow = false

    func throwIfFirst() throws {
        lock.lock()
        defer { lock.unlock() }
        if !didThrow {
            didThrow = true
            throw FixtureError.interrupted
        }
    }
}

private final class RemoteAvailability: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = true

    var available: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

private final class Fixture {
    let root: URL
    let connectionURL: URL
    let projectsURL: URL
    let manifestURL: URL
    let projectURLs: [URL]
    let manifest: BessieProjectTargetMigrationManifest
    let manifestData: Data
    let migration: BessieProjectTargetMigration
    let ownerToken = UUID()
    private let remoteFailure: RemoteFailure?

    var controlPath: String {
        BessieProjectTargetMigration.migrationSSHControlPath(operationID: manifest.operationID)
    }

    init(
        projectCount: Int,
        remoteFailure: RemoteFailure? = nil,
        approvedSourceRoots: [String] = ["/client"],
        legacyConnectionShape: Bool = false
    ) throws {
        self.remoteFailure = remoteFailure
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bessie-target-migration-\(UUID().uuidString)", isDirectory: true)
        let live = root.appendingPathComponent("Live", isDirectory: true)
        connectionURL = live.appendingPathComponent("connections.json")
        projectsURL = live.appendingPathComponent("Projects", isDirectory: true)
        manifestURL = root.appendingPathComponent("manifest.json")
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Backups", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Journals", isDirectory: true), withIntermediateDirectories: true)

        var local = BessieConnectionDefinition.localBessie
        local.connectAtLaunch = false
        let remote = BessieConnectionDefinition(
            id: "hermes-vps",
            name: "Hermes VPS",
            kind: .ssh,
            sshHost: "hermes",
            enabled: true,
            connectAtLaunch: false
        )
        let state = try BessieConnectionState.validated(
            selectedConnectionID: remote.id,
            defaultProjectConnectionID: local.id,
            connections: [local, remote]
        )
        try BessieConnectionStore(url: connectionURL).save(state)
        if legacyConnectionShape {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: connectionURL)) as? [String: Any]
            )
            object.removeValue(forKey: "default_project_connection_id")
            object["future_setting"] = "preserve-me"
            var definitions = try XCTUnwrap(object["connections"] as? [[String: Any]])
            for index in definitions.indices {
                definitions[index].removeValue(forKey: "enabled")
                definitions[index]["future_connection_field"] = definitions[index]["id"] as? String == "local-bessie"
                    ? "local-value"
                    : "remote-value"
            }
            object["connections"] = definitions
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
                .write(to: connectionURL)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: connectionURL.path)

        var urls: [URL] = []
        var mappings: [BessieProjectTargetMigrationManifest.ProjectMapping] = []
        for index in 0..<projectCount {
            let projectID = UUID()
            let folderID = UUID()
            let rootPaneID = UUID()
            let sourcePath = "/client/project-\(index)"
            let targetPath = remoteFailure == .outsideApprovedRoot && index == 0
                ? "/srv/workstreams-old/project-0"
                : "/srv/workstreams/project-\(index)"
            let project = BessieProject(
                id: projectID,
                name: "Project \(index)",
                projectDescription: "Fixture",
                targetConnectionID: "local-bessie",
                folders: [.init(id: folderID, name: "Primary", path: sourcePath, isPrimary: true)],
                tabs: [.init(name: "Work", panes: [
                    .init(id: rootPaneID, label: "Editor", command: "amp", folderID: folderID, placement: .root),
                    .init(label: "Tests", command: "swift test", folderID: folderID, placement: .split(fromPaneID: rootPaneID, direction: .right, ratio: 0.5)),
                ])],
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100 + Double(index))
            )
            let data = try BessieProjectCodec.encode(project)
            let url = projectsURL.appendingPathComponent(projectID.uuidString.lowercased() + ".json")
            try data.write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: index.isMultiple(of: 2) ? 0o640 : 0o600], ofItemAtPath: url.path)
            urls.append(url)
            mappings.append(.init(
                projectID: projectID,
                sourceSHA256: BessieProjectTargetMigration.sha256(data),
                folders: [.init(folderID: folderID, sourcePath: sourcePath, targetPath: targetPath)]
            ))
        }
        projectURLs = urls
        let operationID = UUID()
        manifest = .init(
            operationID: operationID,
            connectionsPath: connectionURL.path,
            projectsPath: projectsURL.path,
            backupPath: root.appendingPathComponent("Backups/\(operationID.uuidString)", isDirectory: true).path,
            journalPath: root.appendingPathComponent("Journals/\(operationID.uuidString).json").path,
            connectionSourceSHA256: BessieProjectTargetMigration.sha256(try Data(contentsOf: connectionURL)),
            sourceConnectionID: "local-bessie",
            targetConnectionID: "hermes-vps",
            expectedProjectCount: projectCount,
            approvedSourceRoots: approvedSourceRoots,
            approvedTargetRoots: ["/srv/workstreams"],
            projects: mappings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL)
        migration = Self.makeMigration(failure: remoteFailure)
    }

    func preflight(
        using migration: BessieProjectTargetMigration? = nil
    ) throws -> BessieProjectTargetMigrationJournal {
        try (migration ?? self.migration).preflight(
            manifest: manifest,
            manifestData: manifestData,
            manifestPath: manifestURL.path,
            sshControlPath: controlPath,
            sshHost: "hermes",
            sshMasterPID: 1234,
            sshOwnerToken: ownerToken
        )
    }

    func makeMigration(
        afterBackupStep: @escaping @Sendable (BessieMigrationBackupStep) throws -> Void = { _ in },
        afterJournalWrite: @escaping @Sendable () throws -> Void = {},
        afterProjectWrite: @escaping @Sendable (Int) throws -> Void = { _ in },
        afterConnectionWrite: @escaping @Sendable () throws -> Void = {}
    ) -> BessieProjectTargetMigration {
        Self.makeMigration(
            failure: remoteFailure,
            afterBackupStep: afterBackupStep,
            afterJournalWrite: afterJournalWrite,
            afterProjectWrite: afterProjectWrite,
            afterConnectionWrite: afterConnectionWrite
        )
    }

    func connectionState() throws -> BessieConnectionState {
        try BessieConnectionStore(url: connectionURL).load()
    }

    func mutateJournal(_ body: (inout [String: Any]) throws -> Void) throws {
        let journalURL = URL(fileURLWithPath: manifest.journalPath)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        try body(&object)
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: journalURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeMigration(
        failure: RemoteFailure?,
        afterBackupStep: @escaping @Sendable (BessieMigrationBackupStep) throws -> Void = { _ in },
        afterJournalWrite: @escaping @Sendable () throws -> Void = {},
        afterProjectWrite: @escaping @Sendable (Int) throws -> Void = { _ in },
        afterConnectionWrite: @escaping @Sendable () throws -> Void = {}
    ) -> BessieProjectTargetMigration {
        BessieProjectTargetMigration(
            remoteInspector: .init { path in
                if path == "/srv/workstreams" {
                    return .init(requestedPath: path, canonicalPath: path, exists: true, isDirectory: true, isSymbolicLink: false)
                }
                switch failure {
                case .missing:
                    return .init(requestedPath: path, canonicalPath: path, exists: false, isDirectory: false, isSymbolicLink: false)
                case .symlink:
                    return .init(requestedPath: path, canonicalPath: path, exists: true, isDirectory: false, isSymbolicLink: true)
                case .noncanonical:
                    return .init(requestedPath: path, canonicalPath: "/srv/real/project", exists: true, isDirectory: true, isSymbolicLink: false)
                case .outsideApprovedRoot, .none:
                    return .init(requestedPath: path, canonicalPath: path, exists: true, isDirectory: true, isSymbolicLink: false)
                }
            },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            afterBackupStep: afterBackupStep,
            afterJournalWrite: afterJournalWrite,
            afterProjectWrite: afterProjectWrite,
            afterConnectionWrite: afterConnectionWrite
        )
    }
}
