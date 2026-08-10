import Foundation
import XCTest
@testable import BessieCore

final class BessieProjectTests: XCTestCase {
    func testValidProjectNormalizesAndRoundTripsWithoutRuntimeState() throws {
        try withProjectDirectory { directory in
            let project = makeProject(
                directory: directory,
                name: "  Project One  ",
                group: "  Client  ",
                label: "  Server  ",
                command: "printf ' exact $TEXT '"
            )

            let normalized = try project.normalized()
            let data = try BessieProjectCodec.encode(normalized)
            let decoded = try BessieProjectCodec.decode(data)
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))

            XCTAssertEqual(normalized.name, "Project One")
            XCTAssertEqual(normalized.group, "Client")
            XCTAssertEqual(normalized.schemaVersion, 3)
            XCTAssertEqual(normalized.targetConnectionID, BessieConnectionDefinition.localBessie.id)
            XCTAssertEqual(normalized.folders.count, 1)
            XCTAssertTrue(normalized.folders[0].isPrimary)
            XCTAssertEqual(normalized.tabs[0].name, "Main")
            XCTAssertEqual(normalized.tabs[0].panes[0].label, "Server")
            XCTAssertEqual(normalized.tabs[0].panes[0].command, "printf ' exact $TEXT '")
            XCTAssertEqual(decoded, normalized)
            XCTAssertFalse(json.contains("workspace_id"))
            XCTAssertFalse(json.contains("tab_id"))
            XCTAssertFalse(json.contains("pane_id"))
            XCTAssertFalse(json.contains("process"))
            XCTAssertFalse(json.contains("agent"))
            XCTAssertFalse(json.contains("environment"))
        }
    }

    func testMigrationEntryPointDispatchesFirstSchemaFixtureAndRejectsFutureVersion() throws {
        let data = Data(Self.versionOneMigrationFixture.utf8)
        let migrated = try BessieProjectMigration.migrate(data)
        XCTAssertEqual(migrated.schemaVersion, BessieProjectSchema.currentVersion)
        XCTAssertEqual(migrated.id, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(migrated.name, "First schema fixture")
        XCTAssertEqual(migrated.group, "  Legacy team  ")
        XCTAssertEqual(migrated.folders, [
            BessieProjectFolder(
                id: migrated.id,
                name: "Primary",
                path: "/tmp/bessie-project-v1-fixture",
                isPrimary: true
            ),
        ])
        XCTAssertNil(migrated.tabs[0].panes[0].folderID)
        XCTAssertEqual(try BessieProjectCodec.decode(data), migrated)

        let roundTripped = try BessieProjectCodec.decode(BessieProjectCodec.encode(migrated))
        XCTAssertEqual(roundTripped, migrated)
        XCTAssertEqual(roundTripped.group, "  Legacy team  ")

        let future = try replacingSchemaVersion(in: data, with: BessieProjectSchema.currentVersion + 1)
        XCTAssertThrowsError(try BessieProjectMigration.migrate(future)) {
            XCTAssertEqual($0 as? BessieProjectSchemaError, .unsupportedVersion(BessieProjectSchema.currentVersion + 1))
        }
    }

    func testSchemaTwoMigrationPinsLegacyHostPathsToLocalInsteadOfSelectedRemote() throws {
        try withProjectDirectory { directory in
            var sourceProject = makeProject(directory: directory)
            sourceProject.targetConnectionID = "hermes-vps"
            let versionTwo = try versionTwoData(from: sourceProject)

            let migrated = try BessieProjectMigration.migrate(versionTwo)

            XCTAssertEqual(migrated.schemaVersion, 3)
            XCTAssertEqual(migrated.targetConnectionID, BessieConnectionDefinition.localBessie.id)
            XCTAssertEqual(migrated.workingDirectory, directory.path)
        }
    }

    func testFutureSchemaFileIsIsolatedWithoutHidingHealthyProjects() throws {
        try withStore { store, directory in
            let healthy = try store.save(makeProject(directory: directory))
            let futureData = try addingJSONField(
                to: replacingSchemaVersion(
                    in: BessieProjectCodec.encode(makeProject(directory: directory)),
                    with: BessieProjectSchema.currentVersion + 1
                ),
                path: [],
                key: "futureField"
            )
            XCTAssertThrowsError(try BessieProjectCodec.decode(futureData)) {
                XCTAssertEqual($0 as? BessieProjectSchemaError, .unsupportedVersion(BessieProjectSchema.currentVersion + 1))
            }
            try futureData.write(to: store.rootURL.appendingPathComponent("future.json"))

            let catalog = try store.list()

            XCTAssertEqual(catalog.projects.map(\.project.id), [healthy.project.id])
            XCTAssertEqual(catalog.issues.map(\.kind), [.unsupportedSchemaVersion])
            XCTAssertEqual(catalog.issues.map(\.filename), ["future.json"])
        }
    }

    func testCurrentSchemaRejectsUnknownRuntimeCredentialAndEnvironmentFields() throws {
        try withProjectDirectory { directory in
            let data = try BessieProjectCodec.encode(makeProject(directory: directory))
            for (path, key) in [
                ([String](), "workspace_id"),
                ([String](), "credentials"),
                (["folders", "0"], "sshConnectionString"),
                (["tabs", "0"], "tab_id"),
                (["tabs", "0", "panes", "0"], "environment"),
                (["tabs", "0", "panes", "0", "placement"], "pane_id"),
            ] {
                let modified = try addingJSONField(to: data, path: path, key: key)
                XCTAssertThrowsError(try BessieProjectCodec.decode(modified)) {
                    guard case .invalidDocument = $0 as? BessieProjectSchemaError else {
                        return XCTFail("Expected strict schema rejection, got \($0)")
                    }
                }
            }
        }
    }

    func testSchemaOneStrictlyRejectsFutureAndRuntimeFieldsBeforeMigration() throws {
        let data = Data(Self.versionOneMigrationFixture.utf8)
        for (path, key) in [
            ([String](), "folders"),
            ([String](), "token"),
            (["tabs", "0", "panes", "0"], "folderID"),
            (["tabs", "0", "panes", "0"], "pane_id"),
        ] {
            let modified = try addingJSONField(to: data, path: path, key: key)
            XCTAssertThrowsError(try BessieProjectCodec.decode(modified)) {
                guard case .invalidDocument = $0 as? BessieProjectSchemaError else {
                    return XCTFail("Expected strict schema-v1 rejection, got \($0)")
                }
            }
        }
    }

    func testValidationRejectsEmptyNamesMissingTabsAndPanes() throws {
        try withProjectDirectory { directory in
            assertIssues(makeProject(directory: directory, name: " \n "), contain: [.emptyName])
            assertIssues(makeProject(directory: directory, tabs: []), contain: [.missingTabs])

            var project = makeProject(directory: directory)
            project.tabs[0].name = "\t"
            project.tabs[0].panes = []
            assertIssues(project, contain: [.emptyName, .missingPanes])
        }
    }

    func testValidationRejectsRelativeMissingAndNonDirectoryWorkingPaths() throws {
        try withProjectDirectory { directory in
            assertIssues(makeProject(directory: directory, workingDirectory: "relative/path"), contain: [.folderNotAbsolute])
            assertIssues(
                makeProject(directory: directory, workingDirectory: directory.appendingPathComponent("missing").path),
                contain: [.folderNotDirectory]
            )
            let file = directory.appendingPathComponent("file")
            try Data().write(to: file)
            assertIssues(makeProject(directory: directory, workingDirectory: file.path), contain: [.folderNotDirectory])
        }
    }

    func testFolderValidationRequiresOnePrimaryUniquePathsAndValidPaneReferences() throws {
        try withProjectDirectory { directory in
            let additional = directory.appendingPathComponent("Additional", isDirectory: true)
            try FileManager.default.createDirectory(at: additional, withIntermediateDirectories: true)
            let primaryID = UUID()
            let additionalID = UUID()
            let timestamp = Date(timeIntervalSince1970: 1_000)
            var project = BessieProject(
                name: "Folders",
                folders: [
                    .init(id: primaryID, name: "Primary", path: directory.path, isPrimary: true),
                    .init(id: additionalID, name: "Additional", path: additional.path),
                ],
                tabs: [.init(name: "Main", panes: [
                    .init(folderID: additionalID, placement: .root),
                ])],
                createdAt: timestamp,
                updatedAt: timestamp
            )

            let normalized = try project.normalized()
            XCTAssertEqual(normalized.workingDirectory(for: normalized.tabs[0].panes[0]), additional.path)
            XCTAssertEqual(
                try BessieProjectCodec.decode(BessieProjectCodec.encode(normalized)),
                normalized
            )

            project.folders[1].path = directory.appendingPathComponent(".").path
            project.folders[1].isPrimary = true
            project.tabs[0].panes[0].folderID = UUID()
            assertIssues(
                project,
                contain: [.invalidPrimaryFolderCount, .duplicateFolderPath, .paneFolderMissing]
            )
        }
    }

    func testValidationRejectsDuplicateTabAndGloballyDuplicatePaneIDs() throws {
        try withProjectDirectory { directory in
            let sharedTabID = UUID()
            let sharedPaneID = UUID()
            let tabs = [
                BessieProjectTab(id: sharedTabID, name: "One", panes: [.init(id: sharedPaneID, placement: .root)]),
                BessieProjectTab(id: sharedTabID, name: "Two", panes: [.init(id: sharedPaneID, placement: .root)]),
            ]
            assertIssues(makeProject(directory: directory, tabs: tabs), contain: [.duplicateTabID, .duplicatePaneID])
        }
    }

    func testValidationRejectsRootAndSplitReferenceFailures() throws {
        try withProjectDirectory { directory in
            let first = UUID()
            let second = UUID()
            let otherTabPane = UUID()
            let tabs = [
                BessieProjectTab(name: "One", panes: [
                    .init(id: first, placement: .split(fromPaneID: second, direction: .right, ratio: 0.5)),
                    .init(id: second, placement: .split(fromPaneID: first, direction: .down, ratio: 0.5)),
                ]),
                BessieProjectTab(name: "Two", panes: [
                    .init(id: otherTabPane, placement: .root),
                    .init(placement: .split(fromPaneID: first, direction: .right, ratio: 0.5)),
                    .init(placement: .split(fromPaneID: UUID(), direction: .right, ratio: 0.5)),
                ]),
            ]

            assertIssues(
                makeProject(directory: directory, tabs: tabs),
                contain: [.invalidRootCount, .splitParentNotEarlier, .splitCycle, .splitParentCrossTab, .splitParentMissing]
            )
            assertIssues(
                makeProject(directory: directory, tabs: [
                    .init(name: "Two roots", panes: [.init(placement: .root), .init(placement: .root)]),
                ]),
                contain: [.invalidRootCount]
            )
        }
    }

    func testValidationRejectsUnsupportedAndNonFiniteRatios() throws {
        try withProjectDirectory { directory in
            for ratio in [0.09, 0.91, Double.nan, Double.infinity, -Double.infinity] {
                let root = UUID()
                let panes = [
                    BessieProjectPane(id: root, placement: .root),
                    BessieProjectPane(placement: .split(fromPaneID: root, direction: .right, ratio: ratio)),
                ]
                assertIssues(makeProject(directory: directory, tabs: [.init(name: "Main", panes: panes)]), contain: [.invalidSplitRatio])
            }

            for ratio in [0.1, 0.9] {
                let root = UUID()
                let panes = [
                    BessieProjectPane(id: root, placement: .root),
                    BessieProjectPane(placement: .split(fromPaneID: root, direction: .right, ratio: ratio)),
                ]
                XCTAssertNoThrow(try makeProject(directory: directory, tabs: [.init(name: "Main", panes: panes)]).normalized())
            }
        }
    }

    func testCommandNormalizationAndNewlineValidationPreserveExactText() throws {
        try withProjectDirectory { directory in
            XCTAssertNil(try makeProject(directory: directory, command: "").normalized().tabs[0].panes[0].command)
            XCTAssertEqual(try makeProject(directory: directory, command: "  echo '$X'  ").normalized().tabs[0].panes[0].command, "  echo '$X'  ")
            assertIssues(makeProject(directory: directory, command: "echo one\necho two"), contain: [.commandContainsLineBreak])
            assertIssues(makeProject(directory: directory, command: "echo one\recho two"), contain: [.commandContainsLineBreak])
        }
    }

    func testStoreAllowsDuplicateNamesWithDistinctUUIDsAndSortsDeterministically() throws {
        try withStore { store, directory in
            let later = makeProject(directory: directory, id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!, name: "same")
            let earlier = makeProject(directory: directory, id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "Same")

            _ = try store.create(later)
            _ = try store.create(earlier)
            let catalog = try store.list()

            XCTAssertEqual(catalog.projects.map(\.project.id), [earlier.id, later.id])
            XCTAssertTrue(catalog.issues.isEmpty)
        }
    }

    func testStoreCreatesUpdatesAndLoadsAtomically() throws {
        try withStore { store, directory in
            let created = try store.create(makeProject(directory: directory))
            var edited = created.project
            edited.projectDescription = "updated"

            let updated = try store.update(edited, expected: created.revision)
            let loaded = try store.load(id: edited.id)

            XCTAssertEqual(loaded.project.projectDescription, "updated")
            XCTAssertEqual(loaded, updated)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path).contains { $0.hasSuffix(".tmp") })
        }
    }

    func testAtomicReplacementFailurePreservesPreviousRecipeAndCleansTemporaryFile() throws {
        try withProjectDirectory { directory in
            let store = BessieProjectStore(
                rootURL: directory.appendingPathComponent("Projects", isDirectory: true),
                atomicReplace: { _, _ in throw AtomicReplacementError.injected }
            )
            let created = try store.create(makeProject(directory: directory))
            let originalData = try Data(contentsOf: created.sourceURL)
            var edited = created.project
            edited.projectDescription = "must not replace"

            XCTAssertThrowsError(try store.update(edited, expected: created.revision)) {
                XCTAssertEqual($0 as? AtomicReplacementError, .injected)
            }

            XCTAssertEqual(try Data(contentsOf: created.sourceURL), originalData)
            XCTAssertEqual(try store.load(id: created.project.id).project, created.project)
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path).contains { $0.hasSuffix(".tmp") }
            )
        }
    }

    func testStaleWriteReturnsBothVersionsAndPreservesExistingContent() throws {
        try withStore { store, directory in
            let first = try store.create(makeProject(directory: directory))
            var winner = first.project
            winner.projectDescription = "winner"
            _ = try store.update(winner, expected: first.revision)

            var stale = first.project
            stale.projectDescription = "stale"
            XCTAssertThrowsError(try store.update(stale, expected: first.revision)) { error in
                guard case .staleWrite(let conflict) = error as? BessieProjectStoreError else {
                    return XCTFail("Expected stale-write conflict, got \(error)")
                }
                XCTAssertEqual(conflict.existing.projectDescription, "winner")
                XCTAssertEqual(conflict.attempted.projectDescription, "stale")
            }
            XCTAssertEqual(try store.load(id: first.project.id).project.projectDescription, "winner")
        }
    }

    func testConcurrentUpdatesAllowExactlyOneWriter() throws {
        try withProjectDirectory { directory in
            let root = directory.appendingPathComponent("Projects", isDirectory: true)
            let firstStore = BessieProjectStore(rootURL: root, now: { Date(timeIntervalSince1970: 2_000) })
            let secondStore = BessieProjectStore(rootURL: root, now: { Date(timeIntervalSince1970: 3_000) })
            let loaded = try firstStore.create(makeProject(directory: directory))
            let results = LockedValues<Result<BessieStoredProject, Error>>()
            let group = DispatchGroup()

            for (store, description) in [(firstStore, "first"), (secondStore, "second")] {
                group.enter()
                DispatchQueue.global().async {
                    defer { group.leave() }
                    var project = loaded.project
                    project.projectDescription = description
                    results.append(Result { try store.update(project, expected: loaded.revision) })
                }
            }
            group.wait()

            let capturedResults = results.values
            XCTAssertEqual(
                capturedResults.filter { if case .success = $0 { true } else { false } }.count,
                1,
                "Results: \(capturedResults)"
            )
            let failures = capturedResults.compactMap { result -> BessieProjectWriteConflict? in
                guard case .failure(BessieProjectStoreError.staleWrite(let conflict)) = result else { return nil }
                return conflict
            }
            XCTAssertEqual(failures.count, 1, "Results: \(capturedResults)")
            XCTAssertTrue(["first", "second"].contains(try firstStore.load(id: loaded.project.id).project.projectDescription))
            if let failure = failures.first {
                XCTAssertTrue(["first", "second"].contains(failure.attempted.projectDescription))
            }
        }
    }

    func testCorruptFileDoesNotHideHealthyProjects() throws {
        try withStore { store, directory in
            let healthy = try store.create(makeProject(directory: directory))
            try Data("not json".utf8).write(to: store.rootURL.appendingPathComponent("corrupt.json"))

            let catalog = try store.list()

            XCTAssertEqual(catalog.projects.map(\.project.id), [healthy.project.id])
            XCTAssertEqual(catalog.issues.count, 1)
            XCTAssertEqual(catalog.issues[0].kind, .corrupt)
            XCTAssertEqual(catalog.issues[0].filename, "corrupt.json")
        }
    }

    func testMissingSavedWorkingDirectoryDoesNotHideProjectFromCatalogOrLoad() throws {
        try withProjectDirectory { directory in
            let workingDirectory = directory.appendingPathComponent("Working", isDirectory: true)
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            let store = BessieProjectStore(rootURL: directory.appendingPathComponent("Projects", isDirectory: true))
            let saved = try store.create(makeProject(directory: workingDirectory))

            try FileManager.default.removeItem(at: workingDirectory)

            let catalog = try store.list()
            XCTAssertEqual(catalog.projects.map(\.project.id), [saved.project.id])
            XCTAssertTrue(catalog.issues.isEmpty)
            XCTAssertEqual(try store.load(id: saved.project.id).project, saved.project)
        }
    }

    func testStoreRejectsMissingWorkingDirectoryBeforeCreateAndUpdate() throws {
        try withStore { store, directory in
            let missingDirectory = directory.appendingPathComponent("Missing", isDirectory: true)
            XCTAssertThrowsError(try store.create(makeProject(directory: missingDirectory))) { error in
                guard let validation = error as? BessieProjectValidationError else {
                    return XCTFail("Expected validation error, got \(error)")
                }
                XCTAssertTrue(validation.issues.contains { $0.code == .folderNotDirectory })
            }

            let saved = try store.create(makeProject(directory: directory))
            var edited = saved.project
            edited.workingDirectory = missingDirectory.path
            XCTAssertThrowsError(try store.update(edited, expected: saved.revision)) { error in
                guard let validation = error as? BessieProjectValidationError else {
                    return XCTFail("Expected validation error, got \(error)")
                }
                XCTAssertTrue(validation.issues.contains { $0.code == .folderNotDirectory })
            }
            XCTAssertEqual(try store.load(id: saved.project.id).project, saved.project)
        }
    }

    func testFilenameMismatchIsIsolatedAndNeverOverwritesCanonicalProject() throws {
        try withStore { store, directory in
            let canonical = try store.create(makeProject(directory: directory, name: "canonical"))
            let mismatch = makeProject(directory: directory, id: canonical.project.id, name: "mismatch")
            let mismatchURL = store.rootURL.appendingPathComponent("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF.json")
            try BessieProjectCodec.encode(mismatch).write(to: mismatchURL)

            let catalog = try store.list()

            XCTAssertEqual(catalog.projects.count, 2)
            XCTAssertEqual(catalog.issues.map(\.kind), [.filenameMismatch, .duplicateEmbeddedID])
            let mismatchedProject = try XCTUnwrap(catalog.projects.first(where: \.filenameMismatch))
            XCTAssertEqual(mismatchedProject.sourceURL.lastPathComponent, mismatchURL.lastPathComponent)
            XCTAssertThrowsError(try store.update(mismatchedProject.project, expected: mismatchedProject.revision)) {
                guard case .filenameMismatch = $0 as? BessieProjectStoreError else {
                    return XCTFail("Expected filename mismatch, got \($0)")
                }
            }
            XCTAssertThrowsError(try store.recoverFilenameMismatch(mismatchedProject)) {
                XCTAssertEqual($0 as? BessieProjectStoreError, .alreadyExists(canonical.project.id))
            }
            let loaded = try store.load(id: canonical.project.id)
            XCTAssertEqual(loaded.project.name, "canonical")
            XCTAssertEqual(loaded.sourceURL, canonical.sourceURL)
            XCTAssertFalse(loaded.filenameMismatch)
            XCTAssertTrue(FileManager.default.fileExists(atPath: mismatchURL.path))
            XCTAssertEqual(
                try BessieProjectCodec.decode(Data(contentsOf: canonical.sourceURL)).name,
                "canonical"
            )
        }
    }

    func testLoneFilenameMismatchCanBeRecoveredToCanonicalFilename() throws {
        try withStore { store, directory in
            let embeddedID = UUID()
            let mismatch = makeProject(directory: directory, id: embeddedID, name: "mismatch")
            let mismatchURL = store.rootURL.appendingPathComponent("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF.json")
            try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
            try BessieProjectCodec.encode(mismatch).write(to: mismatchURL)
            let loaded = try store.load(id: embeddedID)

            let recovered = try store.recoverFilenameMismatch(loaded)

            XCTAssertEqual(recovered.sourceURL.lastPathComponent, embeddedID.uuidString + ".json")
            XCTAssertFalse(recovered.filenameMismatch)
            XCTAssertFalse(FileManager.default.fileExists(atPath: mismatchURL.path))
            XCTAssertEqual(try store.load(id: embeddedID), recovered)
        }
    }

    func testEmbeddedUUIDIsAuthoritativeForLookupAndBlocksCreateCollisions() throws {
        try withStore { store, directory in
            let embeddedID = UUID()
            let mismatch = makeProject(directory: directory, id: embeddedID, name: "mismatch")
            let mismatchURL = store.rootURL.appendingPathComponent("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF.json")
            try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
            try BessieProjectCodec.encode(mismatch).write(to: mismatchURL)

            let loaded = try store.load(id: embeddedID)

            XCTAssertEqual(loaded.project.id, embeddedID)
            XCTAssertTrue(loaded.filenameMismatch)
            XCTAssertThrowsError(try store.create(makeProject(directory: directory, id: embeddedID))) {
                XCTAssertEqual($0 as? BessieProjectStoreError, .alreadyExists(embeddedID))
            }

            let secondURL = store.rootURL.appendingPathComponent("EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE.json")
            try BessieProjectCodec.encode(mismatch).write(to: secondURL)
            XCTAssertThrowsError(try store.load(id: embeddedID)) {
                XCTAssertEqual($0 as? BessieProjectStoreError, .duplicateEmbeddedID(embeddedID))
            }
            XCTAssertThrowsError(try store.recoverFilenameMismatch(loaded)) {
                XCTAssertEqual($0 as? BessieProjectStoreError, .duplicateEmbeddedID(embeddedID))
            }
            XCTAssertTrue(try store.list().issues.contains { $0.kind == .duplicateEmbeddedID && $0.embeddedProjectID == embeddedID })
        }
    }

    func testDuplicateArchiveAndUnarchiveUseFreshIdentityAndConflictRules() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        try withStore(now: now) { store, directory in
            let source = try store.create(makeProject(directory: directory))
            let duplicate = try store.duplicate(source)
            let archived = try store.setArchived(true, project: duplicate)
            let unarchived = try store.setArchived(false, project: archived)

            XCTAssertNotEqual(duplicate.project.id, source.project.id)
            XCTAssertEqual(duplicate.project.name, source.project.name)
            XCTAssertEqual(duplicate.project.tabs, source.project.tabs)
            XCTAssertEqual(duplicate.project.createdAt, now)
            XCTAssertEqual(duplicate.project.updatedAt, now)
            XCTAssertEqual(archived.project.archivedAt, now)
            XCTAssertNil(unarchived.project.archivedAt)
        }
    }

    func testDeleteHandsOffToTrashAndTrashFailurePreservesSource() throws {
        try withProjectDirectory { directory in
            let successRoot = directory.appendingPathComponent("success")
            let trashed = LockedURLs()
            let success = BessieProjectStore(rootURL: successRoot, trash: { url in
                trashed.append(url)
                try FileManager.default.removeItem(at: url)
            })
            let successfulProject = try success.create(makeProject(directory: directory))
            try success.delete(successfulProject)
            XCTAssertEqual(trashed.values, [successfulProject.sourceURL])
            XCTAssertFalse(FileManager.default.fileExists(atPath: successfulProject.sourceURL.path))

            let failureRoot = directory.appendingPathComponent("failure")
            let failure = BessieProjectStore(rootURL: failureRoot, trash: { _ in throw TrashOwnerError.denied })
            let preserved = try failure.create(makeProject(directory: directory))
            XCTAssertThrowsError(try failure.delete(preserved)) {
                XCTAssertEqual($0 as? TrashOwnerError, .denied)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: preserved.sourceURL.path))

            let destructiveRoot = directory.appendingPathComponent("destructive-failure")
            let destructiveFailure = BessieProjectStore(rootURL: destructiveRoot, trash: { url in
                try FileManager.default.removeItem(at: url)
                throw TrashOwnerError.denied
            })
            let restored = try destructiveFailure.create(makeProject(directory: directory))
            XCTAssertThrowsError(try destructiveFailure.delete(restored)) {
                XCTAssertEqual($0 as? TrashOwnerError, .denied)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: restored.sourceURL.path))
            XCTAssertEqual(try destructiveFailure.load(id: restored.project.id).project, restored.project)
        }
    }

    func testDeleteRejectsProjectsFromAnotherInjectedRoot() throws {
        try withProjectDirectory { directory in
            let trashCalls = LockedURLs()
            let first = BessieProjectStore(
                rootURL: directory.appendingPathComponent("first"),
                trash: { trashCalls.append($0) }
            )
            let second = BessieProjectStore(
                rootURL: directory.appendingPathComponent("second"),
                trash: { trashCalls.append($0) }
            )
            let stored = try first.create(makeProject(directory: directory))

            XCTAssertThrowsError(try second.delete(stored)) {
                XCTAssertEqual($0 as? BessieProjectStoreError, .notFound(stored.project.id))
            }
            XCTAssertTrue(trashCalls.values.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stored.sourceURL.path))
        }
    }

    func testDeleteHandsExactOwnedFilenameMismatchToTrash() throws {
        try withProjectDirectory { directory in
            let trashCalls = LockedURLs()
            let store = BessieProjectStore(
                rootURL: directory.appendingPathComponent("Projects"),
                trash: { url in
                    trashCalls.append(url)
                    try FileManager.default.removeItem(at: url)
                }
            )
            let project = makeProject(directory: directory)
            let mismatchURL = store.rootURL.appendingPathComponent("FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF.json")
            try FileManager.default.createDirectory(at: store.rootURL, withIntermediateDirectories: true)
            try BessieProjectCodec.encode(project).write(to: mismatchURL)
            let loaded = try store.load(id: project.id)

            try store.delete(loaded)

            XCTAssertEqual(trashCalls.values, [mismatchURL.standardizedFileURL.resolvingSymlinksInPath()])
            XCTAssertFalse(FileManager.default.fileExists(atPath: mismatchURL.path))
        }
    }

    func testProjectsPathOverrideAndDefaultRootResolution() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertEqual(
            BessieProjectStore.resolveRoot(environment: ["BESSIE_PROJECTS_PATH": "/tmp/bessie-projects"], homeDirectory: home).path,
            "/tmp/bessie-projects"
        )
        XCTAssertEqual(
            BessieProjectStore.resolveRoot(environment: [:], homeDirectory: home).path,
            "/Users/tester/Library/Application Support/Bessie/Projects"
        )
    }

    func testStoreTransactionallyMigratesVersionOneAndRetainsExactBackup() throws {
        try withProjectDirectory { directory in
            let root = directory.appendingPathComponent("Projects", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("11111111-1111-1111-1111-111111111111.json")
            let original = Data(Self.versionOneMigrationFixture.utf8)
            try original.write(to: source)
            let store = BessieProjectStore(rootURL: root)

            let catalog = try store.list()

            XCTAssertEqual(catalog.projects.first?.project.schemaVersion, 3)
            XCTAssertTrue(catalog.issues.isEmpty)
            XCTAssertEqual(try BessieProjectCodec.schemaVersion(in: Data(contentsOf: source)), 3)
            XCTAssertEqual(
                catalog.projects.first?.project.targetConnectionID,
                BessieConnectionDefinition.localBessie.id
            )
            XCTAssertEqual(try BessieProjectCodec.decode(Data(contentsOf: source)).group, "  Legacy team  ")
            XCTAssertEqual(try Data(contentsOf: source.appendingPathExtension("v1-backup")), original)
        }
    }

    func testStoreTransactionallyMigratesVersionTwoAndRetainsExactBackup() throws {
        try withProjectDirectory { directory in
            let root = directory.appendingPathComponent("Projects", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let project = makeProject(directory: directory)
            let source = root.appendingPathComponent("\(project.id.uuidString).json")
            let original = try versionTwoData(from: project)
            try original.write(to: source)

            let catalog = try BessieProjectStore(rootURL: root).list()

            XCTAssertEqual(catalog.projects.first?.project.schemaVersion, 3)
            XCTAssertEqual(catalog.projects.first?.project.targetConnectionID, BessieConnectionDefinition.localBessie.id)
            XCTAssertEqual(try Data(contentsOf: source.appendingPathExtension("v2-backup")), original)
        }
    }

    func testInterruptedMigrationRollsBackCanonicalVersionOneAndSurfacesActionableIssue() throws {
        try withProjectDirectory { directory in
            let root = directory.appendingPathComponent("Projects", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let source = root.appendingPathComponent("11111111-1111-1111-1111-111111111111.json")
            let original = Data(Self.versionOneMigrationFixture.utf8)
            try original.write(to: source)
            let store = BessieProjectStore(rootURL: root, atomicReplace: { _, destination in
                try FileManager.default.removeItem(at: destination)
                throw AtomicReplacementError.injected
            })

            let catalog = try store.list()

            XCTAssertTrue(catalog.projects.isEmpty)
            XCTAssertEqual(catalog.issues.map(\.kind), [.migrationFailed])
            XCTAssertTrue(catalog.issues[0].message.contains("rolled back"))
            XCTAssertEqual(try Data(contentsOf: source), original)
            XCTAssertEqual(try Data(contentsOf: source.appendingPathExtension("v1-backup")), original)
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasSuffix(".tmp") })

            let retriedCatalog = try BessieProjectStore(rootURL: root).list()
            XCTAssertEqual(retriedCatalog.projects.first?.project.schemaVersion, 3)
            XCTAssertTrue(retriedCatalog.issues.isEmpty)

            try Data("changed after rollback".utf8).write(to: source)
            XCTAssertEqual(try Data(contentsOf: source.appendingPathExtension("v1-backup")), original)
        }
    }

    func testStoreRefusesSymlinkedCatalogEntryWithoutTouchingExternalVersionOneTarget() throws {
        try withProjectDirectory { directory in
            let root = directory.appendingPathComponent("Projects", isDirectory: true)
            let external = directory.appendingPathComponent("external-v1.json")
            let original = Data(Self.versionOneMigrationFixture.utf8)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try original.write(to: external)
            let linked = root.appendingPathComponent("linked.json")
            try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: external)

            let catalog = try BessieProjectStore(rootURL: root).list()

            XCTAssertTrue(catalog.projects.isEmpty)
            XCTAssertEqual(catalog.issues.map(\.kind), [.corrupt])
            XCTAssertTrue(catalog.issues[0].message.contains("symbolic links"))
            XCTAssertEqual(try Data(contentsOf: external), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: external.appendingPathExtension("v1-backup").path))
        }
    }
}

private enum TrashOwnerError: Error, Equatable { case denied }
private enum AtomicReplacementError: Error, Equatable { case injected }

private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    var values: [URL] { lock.withLock { storage } }
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []
    var values: [Value] { lock.withLock { storage } }
    func append(_ value: Value) { lock.withLock { storage.append(value) } }
}

private extension BessieProjectTests {
    static let versionOneMigrationFixture = """
    {
      "archivedAt": null,
      "createdAt": "2026-08-01T00:00:00Z",
      "group": "  Legacy team  ",
      "id": "11111111-1111-1111-1111-111111111111",
      "name": "First schema fixture",
      "projectDescription": "Native Bessie schema 1",
      "schemaVersion": 1,
      "tabs": [
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "name": "Main",
          "panes": [
            {
              "command": null,
              "id": "33333333-3333-3333-3333-333333333333",
              "label": null,
              "placement": { "type": "root" }
            }
          ]
        }
      ],
      "updatedAt": "2026-08-01T00:00:00Z",
      "workingDirectory": "/tmp/bessie-project-v1-fixture"
    }
    """

    func makeProject(
        directory: URL,
        id: UUID = UUID(),
        name: String = "Project",
        group: String? = nil,
        label: String? = nil,
        command: String? = nil,
        workingDirectory: String? = nil,
        tabs: [BessieProjectTab]? = nil
    ) -> BessieProject {
        BessieProject(
            id: id,
            name: name,
            projectDescription: "Description",
            group: group,
            workingDirectory: workingDirectory ?? directory.path,
            tabs: tabs ?? [.init(name: "  Main  ", panes: [.init(label: label, command: command, placement: .root)])],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    func assertIssues(
        _ project: BessieProject,
        contain expected: Set<BessieProjectValidationIssue.Code>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try project.normalized(), file: file, line: line) { error in
            guard let validation = error as? BessieProjectValidationError else {
                return XCTFail("Expected validation error, got \(error)", file: file, line: line)
            }
            XCTAssertTrue(expected.isSubset(of: Set(validation.issues.map(\.code))),
                          "Expected \(expected), got \(validation.issues)", file: file, line: line)
        }
    }

    func withProjectDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func withStore(now: Date = Date(timeIntervalSince1970: 1_500), _ body: (BessieProjectStore, URL) throws -> Void) throws {
        try withProjectDirectory { directory in
            let store = BessieProjectStore(
                rootURL: directory.appendingPathComponent("Projects", isDirectory: true),
                now: { now },
                trash: { try FileManager.default.removeItem(at: $0) }
            )
            try body(store, directory)
        }
    }

    func replacingSchemaVersion(in data: Data, with version: Int) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = version
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func versionTwoData(from project: BessieProject) throws -> Data {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: BessieProjectCodec.encode(project)) as? [String: Any]
        )
        object["schemaVersion"] = 2
        object.removeValue(forKey: "targetConnectionID")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func addingJSONField(to data: Data, path: [String], key: String) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func add(_ value: Any, remainingPath: ArraySlice<String>) throws -> Any {
            guard let component = remainingPath.first else {
                var dictionary = try XCTUnwrap(value as? [String: Any])
                dictionary[key] = "forbidden"
                return dictionary
            }
            if let index = Int(component) {
                var array = try XCTUnwrap(value as? [Any])
                array[index] = try add(array[index], remainingPath: remainingPath.dropFirst())
                return array
            }
            var dictionary = try XCTUnwrap(value as? [String: Any])
            dictionary[component] = try add(
                XCTUnwrap(dictionary[component]),
                remainingPath: remainingPath.dropFirst()
            )
            return dictionary
        }
        object = try XCTUnwrap(try add(object, remainingPath: path[...]) as? [String: Any])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
