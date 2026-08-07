import BessieCore
import Foundation
import XCTest
@testable import BessieApp

@MainActor
final class ProjectsViewModelTests: XCTestCase {
    nonisolated(unsafe) private var root: URL!
    nonisolated(unsafe) private var workingDirectory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        workingDirectory = root.appendingPathComponent("working", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testCatalogSearchCoversMetadataFoldersAndCommandsWithoutExposingLegacyGroups() throws {
        let store = makeStore()
        _ = try store.create(project(name: "Ledger", description: "Accounting", group: "Backend", command: "swift test"))
        _ = try store.create(project(name: "Website", description: "Marketing", group: nil, command: "npm run dev"))
        _ = try store.create(project(name: "Named ungrouped", group: "Ungrouped"))
        let model = ProjectsViewModel(store: store)

        model.load()
        XCTAssertEqual(model.projects.map(\.project.name), ["Ledger", "Named ungrouped", "Website"])

        model.searchQuery = "swift"
        XCTAssertEqual(model.filteredProjects.map(\.project.name), ["Ledger"])
        model.searchQuery = "marketing"
        XCTAssertEqual(model.filteredProjects.map(\.project.name), ["Website"])
        model.searchQuery = workingDirectory.path
        XCTAssertEqual(model.filteredProjects.count, 3)
        model.searchQuery = ""
        XCTAssertEqual(model.sections.map(\.name), ["Projects"])
        XCTAssertEqual(model.sections.first?.projects.count, 3)
    }

    func testOfflineCreateEditDuplicateArchiveAndDeleteUseInjectedStore() throws {
        let trashed = LockedURLs()
        let store = makeStore(trash: { trashed.append($0); try FileManager.default.removeItem(at: $0) })
        let model = ProjectsViewModel(store: store)
        model.load()

        model.beginCreate(workingDirectory: workingDirectory.path)
        model.draft?.name = "Local project"
        XCTAssertTrue(model.saveDraft())
        let created = try XCTUnwrap(model.projects.first)

        model.beginEdit(created)
        model.draft?.projectDescription = "Edited offline"
        XCTAssertTrue(model.saveDraft())
        XCTAssertEqual(model.projects.first?.project.projectDescription, "Edited offline")

        model.duplicate(created.project.id)
        XCTAssertEqual(model.projects.count, 2)
        XCTAssertEqual(Set(model.projects.map(\.project.id)).count, 2)

        model.setArchived(true, projectID: created.project.id)
        XCTAssertNotNil(model.projects.first { $0.project.id == created.project.id }?.project.archivedAt)
        model.setArchived(false, projectID: created.project.id)
        XCTAssertNil(model.projects.first { $0.project.id == created.project.id }?.project.archivedAt)

        model.delete(created.project.id)
        XCTAssertEqual(model.projects.count, 1)
        XCTAssertEqual(trashed.values.count, 1)
        XCTAssertTrue(model.storeRoot.path.hasPrefix(root.path))
    }

    func testValidationBlocksSaveWithoutWriting() {
        let model = ProjectsViewModel(store: makeStore())
        model.beginCreate(workingDirectory: "relative/path")
        model.draft?.name = ""

        XCTAssertFalse(model.saveDraft())
        XCTAssertFalse(model.validationMessages.isEmpty)
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.storeRoot.appendingPathComponent("relative/path").path))
    }

    func testStaleRevisionKeepsDraftAndSurfacesConflict() throws {
        let store = makeStore()
        let original = try store.create(project(name: "Shared"))
        let model = ProjectsViewModel(store: store)
        model.load()
        model.beginEdit(try XCTUnwrap(model.projects.first))
        model.draft?.name = "My unsaved name"

        var external = original.project
        external.projectDescription = "Changed elsewhere"
        _ = try store.update(external, expected: original.revision)

        XCTAssertFalse(model.saveDraft())
        XCTAssertEqual(model.draft?.name, "My unsaved name")
        XCTAssertNotNil(model.conflict)
        XCTAssertTrue(model.errorMessage?.contains("changed") == true)
    }

    func testCorruptFilesRemainIssuesAlongsideHealthyProjects() throws {
        let store = makeStore()
        _ = try store.create(project(name: "Healthy"))
        try Data("not-json".utf8).write(to: root.appendingPathComponent("broken.json"))
        let model = ProjectsViewModel(store: store)

        model.load()

        XCTAssertEqual(model.projects.map(\.project.name), ["Healthy"])
        XCTAssertEqual(model.issues.map(\.filename), ["broken.json"])
    }

    func testEditorTabAndPaneOperationsPreserveValidTopology() throws {
        let model = ProjectsViewModel(store: makeStore())
        model.beginCreate(workingDirectory: workingDirectory.path)
        model.draft?.name = "Layout"
        let firstTabID = try XCTUnwrap(model.draft?.tabs.first?.id)
        let rootPaneID = try XCTUnwrap(model.draft?.tabs.first?.panes.first?.id)

        model.addPane(tabID: firstTabID, from: rootPaneID, direction: .right)
        let splitPaneID = try XCTUnwrap(model.draft?.tabs.first?.panes.last?.id)
        model.updatePaneLabel(tabID: firstTabID, paneID: splitPaneID, label: "Tests")
        model.updatePaneCommand(tabID: firstTabID, paneID: splitPaneID, command: "swift test")
        model.updatePaneRatio(tabID: firstTabID, paneID: splitPaneID, ratio: 0.4)
        model.duplicateTab(firstTabID)
        let duplicateID = try XCTUnwrap(model.draft?.tabs.last?.id)
        model.moveTab(duplicateID, by: -1)

        XCTAssertEqual(model.draft?.tabs.count, 2)
        XCTAssertEqual(model.draft?.tabs.first?.id, duplicateID)
        XCTAssertNotEqual(model.draft?.tabs[0].panes[0].id, rootPaneID)
        XCTAssertTrue(model.validationMessages.isEmpty)

        model.removePane(tabID: firstTabID, paneID: splitPaneID)
        XCTAssertEqual(model.draft?.tabs.first(where: { $0.id == firstTabID })?.panes.count, 1)
        XCTAssertTrue(model.validationMessages.isEmpty)
    }

    func testEditorManagesOrderedFoldersAndPaneReferencesWithoutMutatingExistingRuntime() throws {
        let additional = root.appendingPathComponent("additional", isDirectory: true)
        let third = root.appendingPathComponent("third", isDirectory: true)
        try FileManager.default.createDirectory(at: additional, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
        let model = ProjectsViewModel(store: makeStore())
        model.beginCreate(workingDirectory: workingDirectory.path)
        let primaryID = try XCTUnwrap(model.draft?.folders.first?.id)
        let paneID = try XCTUnwrap(model.draft?.tabs.first?.panes.first?.id)
        let tabID = try XCTUnwrap(model.draft?.tabs.first?.id)

        model.addFolders([additional, third])
        let additionalID = try XCTUnwrap(model.draft?.folders[1].id)
        model.renameFolder(additionalID, name: "API")
        model.moveFolder(additionalID, by: 1)
        model.makePrimaryFolder(additionalID)
        model.updatePaneFolder(tabID: tabID, paneID: paneID, folderID: primaryID)

        XCTAssertEqual(model.draft?.folders.map(\.path), [workingDirectory.path, third.path, additional.path])
        XCTAssertEqual(model.draft?.project.primaryFolder?.id, additionalID)
        XCTAssertEqual(model.draft?.project.workingDirectory(for: model.draft!.tabs[0].panes[0]), workingDirectory.path)
        XCTAssertTrue(model.validationMessages.isEmpty)

        model.removeFolder(primaryID)
        XCTAssertNil(model.draft?.tabs[0].panes[0].folderID)
        XCTAssertEqual(model.draft?.project.workingDirectory(for: model.draft!.tabs[0].panes[0]), additional.path)
        XCTAssertTrue(model.validationMessages.isEmpty)
    }

    func testEditorPersistsRemoteTargetAndTargetHostPathWithoutLocalPathValidation() throws {
        let remote = remoteConnection()
        let model = ProjectsViewModel(store: makeStore())
        model.updateConnections(
            definitions: [.localBessie, remote.definition],
            targets: [:],
            activeConnectionID: nil
        )
        model.beginCreate(workingDirectory: workingDirectory.path)
        model.draft?.name = "Remote recipe"

        model.updateTargetConnection(remote.definition.id)
        let primaryID = try XCTUnwrap(model.draft?.project.primaryFolder?.id)
        model.updateFolderPath(primaryID, path: "/srv/workstreams/client-project")

        XCTAssertTrue(model.validationMessages.isEmpty)
        XCTAssertTrue(model.saveDraft())
        XCTAssertEqual(model.projects.first?.project.targetConnectionID, remote.definition.id)
        XCTAssertEqual(
            model.projects.first?.project.workingDirectory,
            "/srv/workstreams/client-project"
        )
    }

    func testRemoteOnlyCreateAndCaptureUseEnabledDefaultProjectHerd() throws {
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = remoteConnection()
        let model = ProjectsViewModel(store: makeStore())
        model.updateConnections(
            definitions: [local, remote.definition],
            targets: [remote.definition.id: .init(
                connection: remote,
                snapshot: .captureLaunchFixture(workingDirectory: "/srv/bessie/project"),
                remoteFileAccess: nil
            )],
            activeConnectionID: remote.definition.id,
            defaultProjectConnectionID: remote.definition.id
        )

        model.beginCreate(workingDirectory: "/srv/bessie/new")
        XCTAssertEqual(model.draft?.targetConnectionID, remote.definition.id)
        model.discardDraft()

        XCTAssertTrue(model.beginCaptureCurrentWorkspace())
        XCTAssertEqual(model.draft?.targetConnectionID, remote.definition.id)
        XCTAssertEqual(model.draft?.workingDirectory, "/srv/bessie/project")
    }

    func testDisabledProjectTargetRemainsEditableButCannotLaunchOrStart() throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Disabled local"))
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = remoteConnection()
        let readiness = FakeProjectLaunchTargetReadiness()
        let model = ProjectsViewModel(store: store)
        model.configureLaunchTargetReadiness(
            resolve: readiness.resolve,
            reportFailure: { _ in }
        )
        model.load()
        model.updateConnections(
            definitions: [local, remote.definition],
            targets: [:],
            activeConnectionID: nil,
            defaultProjectConnectionID: remote.definition.id
        )

        model.beginEdit(stored)

        XCTAssertEqual(model.draftTargetConnection?.id, local.id)
        XCTAssertEqual(model.projectTargetConnections.map(\.id), [local.id, remote.definition.id])
        XCTAssertTrue(model.draftTargetUnavailableReason?.contains("disabled") == true)
        model.discardDraft()
        XCTAssertFalse(model.launchImmediately(stored.project.id))
        XCTAssertEqual(readiness.callCount, 0)
        XCTAssertTrue(model.notice?.contains("disabled") == true)
        XCTAssertFalse(model.notice?.contains("Manage Projects") == true)
    }

    func testRetargetingDisabledProjectToEnabledRemotePreservesPathsAndTopology() throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Retarget"))
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = remoteConnection()
        let model = ProjectsViewModel(store: store)
        model.load()
        model.updateConnections(
            definitions: [local, remote.definition],
            targets: [:],
            activeConnectionID: nil,
            defaultProjectConnectionID: remote.definition.id
        )
        model.beginEdit(stored)
        let originalFolders = model.draft?.folders
        let originalTabs = model.draft?.tabs

        model.updateTargetConnection(remote.definition.id)

        XCTAssertEqual(model.draft?.folders, originalFolders)
        XCTAssertEqual(model.draft?.tabs, originalTabs)
        XCTAssertEqual(model.draft?.targetConnectionID, remote.definition.id)
    }

    func testOpenAvailabilityValidatesFoldersOnTheirTargetMachine() throws {
        let store = makeStore()
        let valid = try store.create(project(name: "Valid"))
        var invalidProject = project(name: "Invalid")
        invalidProject.workingDirectory = root.appendingPathComponent("missing").path
        try store.createForCatalogTesting(invalidProject)
        var remoteProject = project(name: "Remote")
        remoteProject.targetConnectionID = "remote"
        remoteProject.workingDirectory = "/srv/bessie/remote-only"
        try store.createForCatalogTesting(remoteProject)
        let service = FakeProjectLaunchService()
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()

        XCTAssertFalse(model.canOpenProject(valid.project.id))

        model.updateConnection(connection(identity: .init(version: "0.7.4", protocolVersion: 19)), snapshot: .launchFixture)
        XCTAssertFalse(model.canOpenProject(valid.project.id))

        let remote = remoteConnection()
        model.updateConnections(
            definitions: [.localBessie, remote.definition],
            targets: [
                BessieConnectionDefinition.localBessie.id: .init(
                    connection: connection(), snapshot: .launchFixture, remoteFileAccess: nil
                ),
                remote.definition.id: .init(connection: remote, snapshot: .launchFixture, remoteFileAccess: nil),
            ],
            activeConnectionID: BessieConnectionDefinition.localBessie.id
        )
        XCTAssertTrue(model.canOpenProject(valid.project.id))
        XCTAssertFalse(model.canOpenProject(invalidProject.id))
        XCTAssertTrue(model.canOpenProject(remoteProject.id))

        model.updateConnections(
            definitions: [.localBessie, remote.definition],
            targets: [BessieConnectionDefinition.localBessie.id: .init(
                connection: connection(), snapshot: .launchFixture, remoteFileAccess: nil
            )],
            activeConnectionID: BessieConnectionDefinition.localBessie.id
        )
        XCTAssertFalse(model.canOpenProject(remoteProject.id))
        XCTAssertTrue(model.openUnavailableReason(for: remoteProject.id).contains("Connect Remote"))
    }

    func testImmediateLocalLaunchBypassesCommandReview() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Direct local", command: "swift test --filter Exact"))
        let service = FakeProjectLaunchService()
        service.result = .success(materializationResult(project: stored.project))
        let readiness = FakeProjectLaunchTargetReadiness()
        let model = ProjectsViewModel(store: store, launchService: service)
        model.configureLaunchTargetReadiness(
            resolve: readiness.resolve,
            reportFailure: { _ in }
        )
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        XCTAssertTrue(model.launchImmediately(stored.project.id))
        await eventually { model.navigationHandoff != nil }

        XCTAssertNil(model.launchReview)
        XCTAssertEqual(readiness.callCount, 0)
        XCTAssertEqual(service.launchCount, 1)
        XCTAssertEqual(service.lastConnection, connection())
        XCTAssertEqual(model.navigationHandoff?.workspaceID, "runtime-workspace-exact")
    }

    func testConfiguredOnDemandLocalTargetStartsThenMaterializes() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "On-demand local"))
        let localOnDemand = BessieConnectionDefinition(
            id: BessieConnectionDefinition.localBessie.id,
            name: "This Mac",
            kind: .local,
            session: BessieCompatibility.sessionName,
            connectAtLaunch: false
        )
        let materializationConnection = connection(definition: localOnDemand)
        let target = ProjectLaunchTarget(
            connection: materializationConnection,
            snapshot: .launchFixture,
            remoteFileAccess: nil
        )
        let readiness = FakeProjectLaunchTargetReadiness()
        let service = FakeProjectLaunchService()
        service.result = .success(materializationResult(
            project: stored.project,
            connection: materializationConnection
        ))
        let model = ProjectsViewModel(store: store, launchService: service)
        var reportedFailures: [String] = []
        model.configureLaunchTargetReadiness(
            resolve: readiness.resolve,
            reportFailure: { reportedFailures.append($0) }
        )
        model.load()
        model.updateConnections(
            definitions: [localOnDemand],
            targets: [:],
            activeConnectionID: nil
        )

        XCTAssertTrue(model.launchImmediately(stored.project.id))
        await eventually { readiness.callCount == 1 }
        XCTAssertEqual(readiness.connectionIDs, [BessieConnectionDefinition.localBessie.id])
        XCTAssertEqual(model.opening?.projectID, stored.project.id)
        XCTAssertEqual(service.launchCount, 0)

        readiness.succeed(target)
        await eventually { model.navigationHandoff != nil }

        XCTAssertEqual(service.launchCount, 1)
        XCTAssertEqual(service.lastConnection, materializationConnection)
        XCTAssertTrue(reportedFailures.isEmpty)
    }

    func testRepeatedImmediateActivationWhileConnectingStartsAndMaterializesOnce() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Connecting once"))
        var localOnDemand = BessieConnectionDefinition.localBessie
        localOnDemand.connectAtLaunch = false
        let materializationConnection = connection(definition: localOnDemand)
        let readiness = FakeProjectLaunchTargetReadiness()
        let service = FakeProjectLaunchService()
        service.waitForCancellation = true
        let model = ProjectsViewModel(store: store, launchService: service)
        model.configureLaunchTargetReadiness(
            resolve: readiness.resolve,
            reportFailure: { _ in }
        )
        model.load()
        model.updateConnections(definitions: [localOnDemand], targets: [:], activeConnectionID: nil)

        XCTAssertTrue(model.launchImmediately(stored.project.id))
        XCTAssertTrue(model.launchImmediately(stored.project.id))
        await eventually { readiness.callCount == 1 }

        readiness.succeed(ProjectLaunchTarget(
            connection: materializationConnection,
            snapshot: .launchFixture,
            remoteFileAccess: nil
        ))
        await eventually { service.launchCount == 1 }
        XCTAssertTrue(model.launchImmediately(stored.project.id))
        XCTAssertEqual(readiness.callCount, 1)
        XCTAssertEqual(service.launchCount, 1)

        model.cancelLaunch()
        await eventually { model.launchFailure != nil }
    }

    func testTargetStartupReadinessFailuresAreSpecificAndNeverMaterialize() async throws {
        let cases: [(ProjectLaunchTargetReadinessError, String)] = [
            (
                .startupFailed(connectionName: "This Mac", detail: "Bundled Herdr exited."),
                "could not start This Mac"
            ),
            (
                .timedOut(connectionName: "This Mac", seconds: 1),
                "within 1 second"
            ),
            (
                .incompatible(connectionName: "This Mac", detail: "Protocol 18 is unsupported."),
                "incompatible with this Bessie build"
            ),
            (
                .unavailable(connectionName: "This Mac", detail: "The runtime is missing."),
                "This Mac is unavailable"
            ),
        ]

        for (index, readinessFailure) in cases.enumerated() {
            let store = makeStore()
            let stored = try store.create(project(name: "Readiness failure \(index)"))
            var localOnDemand = BessieConnectionDefinition.localBessie
            localOnDemand.connectAtLaunch = false
            let service = FakeProjectLaunchService()
            let model = ProjectsViewModel(store: store, launchService: service)
            var reportedFailure: String?
            model.configureLaunchTargetReadiness(
                resolve: { _ in throw readinessFailure.0 },
                reportFailure: { reportedFailure = $0 }
            )
            model.load()
            model.updateConnections(definitions: [localOnDemand], targets: [:], activeConnectionID: nil)

            XCTAssertTrue(model.launchImmediately(stored.project.id))
            await eventually { model.opening == nil }

            XCTAssertEqual(service.launchCount, 0)
            XCTAssertTrue(reportedFailure?.contains(readinessFailure.1) == true, reportedFailure ?? "No failure")
            XCTAssertFalse(reportedFailure?.contains("Manage Projects") == true)
        }
    }

    func testImmediateLaunchRejectsGenuinelyMissingTargetWithoutStartingAnything() throws {
        let store = makeStore()
        var missingTarget = project(name: "Missing herd")
        missingTarget.targetConnectionID = "removed-herd"
        try store.createForCatalogTesting(missingTarget)
        let readiness = FakeProjectLaunchTargetReadiness()
        let model = ProjectsViewModel(store: store)
        model.configureLaunchTargetReadiness(
            resolve: readiness.resolve,
            reportFailure: { _ in }
        )
        model.load()
        model.updateConnections(definitions: [.localBessie], targets: [:], activeConnectionID: nil)

        XCTAssertFalse(model.launchImmediately(missingTarget.id))
        XCTAssertEqual(readiness.callCount, 0)
        XCTAssertTrue(model.notice?.contains("unconfigured herd (removed-herd)") == true)
    }

    func testOnDemandLaunchValidatesLocalFolderBeforeStartingTarget() throws {
        let store = makeStore()
        var invalidLocal = project(name: "Missing local folder")
        invalidLocal.workingDirectory = root.appendingPathComponent("does-not-exist").path
        try store.createForCatalogTesting(invalidLocal)
        var localOnDemand = BessieConnectionDefinition.localBessie
        localOnDemand.connectAtLaunch = false
        let readiness = FakeProjectLaunchTargetReadiness()
        let model = ProjectsViewModel(store: store)
        model.configureLaunchTargetReadiness(
            resolve: readiness.resolve,
            reportFailure: { _ in }
        )
        model.load()
        model.updateConnections(definitions: [localOnDemand], targets: [:], activeConnectionID: nil)

        XCTAssertFalse(model.launchImmediately(invalidLocal.id))
        XCTAssertEqual(readiness.callCount, 0)
        XCTAssertTrue(model.notice?.contains("local folder or recipe settings") == true)
    }

    func testImmediateRemoteLaunchUsesConfiguredHerdrConnectionAndRemotePath() async throws {
        let store = makeStore()
        var remoteProject = project(name: "Direct remote", command: "swift test --filter Exact")
        remoteProject.targetConnectionID = "remote"
        remoteProject.workingDirectory = "/srv/bessie/remote-only"
        try store.createForCatalogTesting(remoteProject)
        let remote = remoteConnection()
        let service = FakeProjectLaunchService()
        service.result = .success(materializationResult(project: remoteProject, connection: remote))
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnections(
            definitions: [.localBessie, remote.definition],
            targets: [
                BessieConnectionDefinition.localBessie.id: .init(
                    connection: connection(), snapshot: .launchFixture, remoteFileAccess: nil
                ),
                remote.definition.id: .init(connection: remote, snapshot: .launchFixture, remoteFileAccess: nil),
            ],
            activeConnectionID: BessieConnectionDefinition.localBessie.id
        )

        XCTAssertTrue(model.launchImmediately(remoteProject.id))
        await eventually { model.navigationHandoff != nil }

        XCTAssertNil(model.launchReview)
        XCTAssertEqual(service.launchCount, 1)
        XCTAssertEqual(service.lastConnection, remote)
        XCTAssertEqual(service.lastProject?.workingDirectory, "/srv/bessie/remote-only")
        XCTAssertEqual(model.progress?.stage, .creatingWorkspace)
        XCTAssertEqual(model.navigationHandoff?.connection.definition.kind, .ssh)
        XCTAssertEqual(model.navigationHandoff?.workspaceID, "runtime-workspace-exact")
    }

    func testCommandProjectRequiresReviewBeforeLaunch() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Reviewed", command: "swift test --filter Exact"))
        let service = FakeProjectLaunchService()
        service.result = .success(materializationResult(project: stored.project))
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        XCTAssertEqual(model.launchReview?.project.id, stored.project.id)
        XCTAssertEqual(model.launchReview?.connectionLabel, "This Mac")
        XCTAssertEqual(service.launchCount, 0)

        model.confirmLaunchReview()
        await eventually { service.launchCount == 1 }

        XCTAssertNil(model.launchReview)
        XCTAssertEqual(service.launchCount, 1)
    }

    func testCancelCommandProjectReviewDoesNotLaunch() throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Reviewed", command: "printf safe"))
        let service = FakeProjectLaunchService()
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        model.cancelLaunchReview()

        XCTAssertNil(model.launchReview)
        XCTAssertEqual(service.launchCount, 0)
    }

    func testProgressAndCompleteLaunchNavigateByExactReturnedIDs() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Shell only"))
        let service = FakeProjectLaunchService()
        service.result = .success(materializationResult(project: stored.project))
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        await eventually { model.navigationHandoff != nil }

        XCTAssertEqual(model.progress?.stage, .creatingWorkspace)
        XCTAssertEqual(model.navigationHandoff?.workspaceID, "runtime-workspace-exact")
        XCTAssertEqual(model.navigationHandoff?.tabID, "runtime-tab-exact")
        XCTAssertEqual(model.navigationHandoff?.paneID, "runtime-pane-exact")
        XCTAssertEqual(model.runningInstance(for: stored.project.id)?.workspaceID, "runtime-workspace-exact")

        model.consumeNavigationHandoff()
        model.openRunningWorkspace(stored.project.id)
        XCTAssertEqual(model.navigationHandoff?.workspaceID, "runtime-workspace-exact")
        XCTAssertEqual(service.launchCount, 1)

        model.updateConnection(connection(), snapshot: .emptyLaunchFixture)
        XCTAssertNil(model.runningInstance(for: stored.project.id))
    }

    func testCancellationBeforeMutationLeavesNoRequest() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Cancel"))
        let service = FakeProjectLaunchService()
        service.waitForCancellation = true
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        await eventually { model.isOpening(stored.project.id) }
        model.cancelLaunch()
        await eventually { model.launchFailure != nil }

        XCTAssertEqual(service.mutationRequestCount, 0)
        XCTAssertEqual(model.launchFailure?.failure.ownerError, .cancelled)
    }

    func testInFlightLaunchRejectsDuplicateMaterializationRequest() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Single launch"))
        let service = FakeProjectLaunchService()
        service.waitForCancellation = true
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        await eventually { model.isOpening(stored.project.id) && service.launchCount == 1 }
        XCTAssertFalse(model.canOpenProject(stored.project.id))
        model.requestOpen(stored.project.id)

        XCTAssertEqual(service.launchCount, 1)
        model.cancelLaunch()
        await eventually { model.launchFailure != nil }
    }

    func testPartialFailureSurfacesExactIDsCommandStateAndDisablesUnsafeRetry() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Partial", command: "make run"))
        let service = FakeProjectLaunchService()
        service.result = .failure(partialFailure(project: stored.project))
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        model.confirmLaunchReview()
        await eventually { model.launchFailure != nil }

        let failure = try XCTUnwrap(model.launchFailure)
        XCTAssertEqual(failure.failure.stage, .submittingCommandEnter)
        XCTAssertEqual(failure.failure.partialResult.workspaceID, "runtime-workspace-exact")
        XCTAssertTrue(failure.failure.partialResult.commands[0].textSubmitted)
        XCTAssertTrue(failure.failure.partialResult.commands[0].echoConfirmed)
        XCTAssertFalse(failure.failure.partialResult.commands[0].enterSubmitted)
        XCTAssertFalse(failure.canRetry)

        model.openPartialWorkspace()
        XCTAssertEqual(model.navigationHandoff?.workspaceID, "runtime-workspace-exact")
        XCTAssertEqual(model.navigationHandoff?.paneID, "runtime-pane-exact")

        let reconnected = BessieProjectMaterializationConnection(
            definition: .localBessie,
            socketPath: connection().socketPath,
            generation: UUID(),
            identity: connection().identity
        )
        model.updateConnection(reconnected, snapshot: .launchFixture)
        XCTAssertFalse(model.canOpenPartialWorkspace)
        XCTAssertFalse(model.canRetryLaunchFailure)
        model.openPartialWorkspace()
        XCTAssertNil(model.navigationHandoff)
    }

    func testFilenameMismatchCanBeRecoveredWithoutReplacingCanonicalNeighbor() throws {
        let store = makeStore()
        let project = project(name: "Mismatch")
        let wrongURL = root.appendingPathComponent("wrong-name.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try BessieProjectCodec.encode(project).write(to: wrongURL)
        let model = ProjectsViewModel(store: store)
        model.load()

        XCTAssertEqual(model.issues.first?.kind, .filenameMismatch)
        model.recoverFilenameMismatch(project.id)

        XCTAssertTrue(model.issues.isEmpty)
        XCTAssertEqual(model.projects.first?.sourceURL.lastPathComponent, "\(project.id.uuidString).json")
    }

    func testCommandPaletteContainsProjectsNavigation() {
        let herd = BessieKeyboardShortcutRouter.commands.first { $0.command == .showHerd }
        let command = BessieKeyboardShortcutRouter.commands.first { $0.command == .projectsPicker }
        let capture = BessieKeyboardShortcutRouter.commands.first { $0.command == .saveCurrentWorkspaceAsProject }
        XCTAssertEqual(herd?.title, "The herd")
        XCTAssertTrue(herd?.matches("home agents") == true)
        XCTAssertEqual(command?.title, "Manage projects")
        XCTAssertTrue(command?.matches("project recipes") == true)
        XCTAssertEqual(capture?.title, "Create project from current workspace…")
        XCTAssertTrue(capture?.matches("capture panes") == true)
        XCTAssertEqual(ProductDestination.navigationTarget(for: .projectsPicker), .projects)
    }

    func testCaptureAvailabilityIsHonestAndCapturedDraftSavesAsNewProject() throws {
        let model = ProjectsViewModel(store: makeStore())
        XCTAssertFalse(model.canCaptureCurrentWorkspace)
        XCTAssertEqual(model.captureUnavailableReason, "Connect to Herdr before saving a workspace as a Project.")

        model.updateConnection(connection(), snapshot: .captureLaunchFixture(workingDirectory: workingDirectory.path))
        XCTAssertTrue(model.canCaptureCurrentWorkspace)
        XCTAssertNil(model.captureUnavailableReason)
        XCTAssertTrue(model.beginCaptureCurrentWorkspace())

        let draft = try XCTUnwrap(model.draft)
        XCTAssertNil(draft.revision)
        XCTAssertEqual(draft.name, "Captured workspace")
        XCTAssertEqual(draft.workingDirectory, workingDirectory.path)
        XCTAssertEqual(draft.project.targetConnectionID, BessieConnectionDefinition.localBessie.id)
        XCTAssertTrue(draft.tabs.flatMap(\.panes).allSatisfy { $0.command == nil })
        XCTAssertTrue(model.saveDraft())
        XCTAssertEqual(model.projects.count, 1)
        XCTAssertEqual(model.projects[0].project.id, draft.project.id)
    }

    func testCaptureRefusesStaleSnapshotAfterDisconnect() {
        let model = ProjectsViewModel(store: makeStore())
        model.updateConnection(nil, snapshot: .captureLaunchFixture(workingDirectory: workingDirectory.path))

        XCTAssertFalse(model.beginCaptureCurrentWorkspace())
        XCTAssertNil(model.draft)
        XCTAssertEqual(model.notice, "Connect to Herdr before saving a workspace as a Project.")
    }

    private func makeStore(trash: @escaping @Sendable (URL) throws -> Void = { _ in }) -> BessieProjectStore {
        BessieProjectStore(rootURL: root, trash: trash)
    }

    private func project(
        name: String,
        description: String = "",
        group: String? = nil,
        command: String? = nil
    ) -> BessieProject {
        BessieProject(
            name: name,
            projectDescription: description,
            group: group,
            workingDirectory: workingDirectory.path,
            tabs: [
                BessieProjectTab(
                    name: "Main",
                    panes: [BessieProjectPane(label: "Shell", command: command, placement: .root)]
                ),
            ]
        )
    }

    private func connection(
        definition: BessieConnectionDefinition = .localBessie,
        identity: HerdrServerIdentity = .init(version: "0.8.0", protocolVersion: 19)
    )
        -> BessieProjectMaterializationConnection
    {
        BessieProjectMaterializationConnection(
            definition: definition,
            socketPath: "/tmp/bessie-project-tests.sock",
            generation: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            identity: identity
        )
    }

    private func remoteConnection() -> BessieProjectMaterializationConnection {
        BessieProjectMaterializationConnection(
            definition: .init(
                id: "remote", name: "Remote", kind: .ssh,
                sshHost: "example", session: "bessie"
            ),
            socketPath: "/tmp/bessie-remote-project-tests.sock",
            generation: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            identity: .init(version: "0.8.0", protocolVersion: 19)
        )
    }

    private func materializationResult(
        project: BessieProject,
        connection materializationConnection: BessieProjectMaterializationConnection? = nil
    ) -> BessieProjectMaterializationResult {
        let tab = project.tabs[0]
        let pane = tab.panes[0]
        let materializationConnection = materializationConnection ?? connection()
        return BessieProjectMaterializationResult(
            plan: .init(project: project, connection: materializationConnection),
            workspaceID: "runtime-workspace-exact",
            tabIDsByRecipeID: [tab.id: "runtime-tab-exact"],
            paneIDsByRecipeID: [pane.id: "runtime-pane-exact"],
            commands: [],
            verificationFacts: [],
            finalSnapshot: .launchFixture
        )
    }

    private func partialFailure(project: BessieProject) -> BessieProjectMaterializationFailure {
        let pane = project.tabs[0].panes[0]
        var command = BessieProjectCommandMaterialization(
            recipePaneID: pane.id,
            runtimePaneID: "runtime-pane-exact",
            command: pane.command!
        )
        command.readinessConfirmed = true
        command.textSubmitted = true
        command.echoConfirmed = true
        return BessieProjectMaterializationFailure(
            stage: .submittingCommandEnter,
            attempt: .command(paneID: pane.id),
            ownerError: .herdr(.connectionClosed),
            partialResult: .init(
                projectID: project.id,
                connectionID: BessieConnectionDefinition.localBessie.id,
                socketPath: "/tmp/bessie-project-tests.sock",
                generation: connection().generation,
                workspaceID: "runtime-workspace-exact",
                tabIDsByRecipeID: [project.tabs[0].id: "runtime-tab-exact"],
                paneIDsByRecipeID: [pane.id: "runtime-pane-exact"],
                commands: [command],
                mutationOutcome: .outcomeUnknown,
                freshSnapshot: .launchFixture,
                lastVerifiedSnapshot: .launchFixture
            )
        )
    }

    private func eventually(
        timeout: TimeInterval = 2,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate())
    }
}

private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    var values: [URL] { lock.withLock { storage } }
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
}

@MainActor
private final class FakeProjectLaunchTargetReadiness {
    private var continuation: CheckedContinuation<ProjectLaunchTarget, Error>?
    private(set) var connectionIDs: [String] = []
    var callCount: Int { connectionIDs.count }

    func resolve(connectionID: String) async throws -> ProjectLaunchTarget {
        connectionIDs.append(connectionID)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed(_ target: ProjectLaunchTarget) {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: target)
    }
}

private final class FakeProjectLaunchService: ProjectLaunchServicing, @unchecked Sendable {
    private let lock = NSLock()
    var result: Result<BessieProjectMaterializationResult, BessieProjectMaterializationFailure>?
    var waitForCancellation = false
    private(set) var launchCount = 0
    private(set) var mutationRequestCount = 0
    private var materializationConnection: BessieProjectMaterializationConnection?
    private var materializedProject: BessieProject?
    var lastConnection: BessieProjectMaterializationConnection? {
        lock.withLock { materializationConnection }
    }
    var lastProject: BessieProject? { lock.withLock { materializedProject } }

    func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        remoteFileAccess _: SSHRemoteFileAccess?,
        onProgress: @escaping @Sendable (BessieProjectMaterializationProgressFact) -> Void
    ) throws -> BessieProjectMaterializationResult {
        lock.withLock {
            launchCount += 1
            materializationConnection = connection
            materializedProject = project
        }
        onProgress(.init(
            stage: .creatingWorkspace,
            attempt: .project(project.id),
            workspaceID: nil,
            tabIDsByRecipeID: [:],
            paneIDsByRecipeID: [:]
        ))
        if waitForCancellation {
            while !withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) {
                Thread.sleep(forTimeInterval: 0.005)
            }
            throw BessieProjectMaterializationFailure(
                stage: .creatingWorkspace,
                attempt: .project(project.id),
                ownerError: .cancelled,
                partialResult: .init(
                    projectID: project.id,
                    connectionID: connection.definition.id,
                    socketPath: connection.socketPath,
                    generation: connection.generation,
                    workspaceID: nil,
                    tabIDsByRecipeID: [:],
                    paneIDsByRecipeID: [:],
                    commands: [],
                    mutationOutcome: .notAttempted,
                    freshSnapshot: nil,
                    lastVerifiedSnapshot: nil
                )
            )
        }
        lock.withLock { mutationRequestCount += 1 }
        guard let result else { fatalError("Fake launch result was not configured") }
        return try result.get()
    }
}

private extension BessieProjectStore {
    func createForCatalogTesting(_ project: BessieProject) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let url = rootURL.appendingPathComponent("\(project.id.uuidString).json")
        try BessieProjectCodec.encode(project).write(to: url)
    }
}

private extension HerdrSnapshot {
    static let emptyLaunchFixture = HerdrSnapshot(
        version: "0.8.0",
        protocolVersion: 19,
        focusedWorkspaceID: nil,
        focusedTabID: nil,
        focusedPaneID: nil,
        workspaces: [],
        tabs: [],
        panes: [],
        layouts: [],
        agents: []
    )

    static let launchFixture = HerdrSnapshot(
        version: "0.8.0",
        protocolVersion: 19,
        focusedWorkspaceID: "runtime-workspace-exact",
        focusedTabID: "runtime-tab-exact",
        focusedPaneID: "runtime-pane-exact",
        workspaces: [.object([
            "workspace_id": .string("runtime-workspace-exact"), "number": .number(1),
            "label": .string("Project"), "focused": .bool(true), "pane_count": .number(1),
            "tab_count": .number(1), "active_tab_id": .string("runtime-tab-exact"),
            "agent_status": .string("idle"),
        ])],
        tabs: [.object([
            "tab_id": .string("runtime-tab-exact"), "workspace_id": .string("runtime-workspace-exact"),
            "number": .number(1), "label": .string("Main"), "focused": .bool(true),
            "pane_count": .number(1), "agent_status": .string("idle"),
        ])],
        panes: [.object([
            "pane_id": .string("runtime-pane-exact"), "terminal_id": .string("terminal-exact"),
            "workspace_id": .string("runtime-workspace-exact"), "tab_id": .string("runtime-tab-exact"),
            "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1),
            "cwd": .string("/tmp"),
        ])],
        layouts: [],
        agents: []
    )

    static func captureLaunchFixture(workingDirectory: String) -> HerdrSnapshot {
        HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "captured-workspace", focusedTabID: "captured-tab", focusedPaneID: "captured-pane",
        workspaces: [.object([
            "workspace_id": .string("captured-workspace"), "number": .number(1),
            "label": .string("Captured workspace"), "focused": .bool(true), "pane_count": .number(1),
            "tab_count": .number(1), "active_tab_id": .string("captured-tab"), "agent_status": .string("idle"),
        ])],
        tabs: [.object([
            "tab_id": .string("captured-tab"), "workspace_id": .string("captured-workspace"),
            "number": .number(1), "label": .string("Main"), "focused": .bool(true),
            "pane_count": .number(1), "agent_status": .string("idle"),
        ])],
        panes: [.object([
            "pane_id": .string("captured-pane"), "terminal_id": .string("captured-terminal"),
            "workspace_id": .string("captured-workspace"), "tab_id": .string("captured-tab"),
            "focused": .bool(true), "label": .string("Shell"), "agent_status": .string("idle"),
            "revision": .number(1), "cwd": .string(workingDirectory),
        ])],
        layouts: [.object([
            "workspace_id": .string("captured-workspace"), "tab_id": .string("captured-tab"),
            "zoomed": .bool(false), "focused_pane_id": .string("captured-pane"),
            "panes": .array([.object([
                "pane_id": .string("captured-pane"), "focused": .bool(true),
                "rect": .object(["x": .number(0), "y": .number(0), "width": .number(80), "height": .number(24)]),
            ])]),
            "splits": .array([]),
        ])],
        agents: []
        )
    }
}
