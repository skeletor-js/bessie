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

    func testCatalogSearchAndGroupingCoverMetadataAndCommands() throws {
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
        XCTAssertEqual(model.sections.map(\.name), ["Backend", "Ungrouped", "Ungrouped"])
        XCTAssertEqual(Set(model.sections.map(\.id)).count, 3)
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

    func testOpenIsDisabledWhenDisconnectedIncompatibleOrInvalid() throws {
        let store = makeStore()
        let valid = try store.create(project(name: "Valid"))
        var invalidProject = project(name: "Invalid")
        invalidProject.workingDirectory = root.appendingPathComponent("missing").path
        try store.createForCatalogTesting(invalidProject)
        let service = FakeProjectLaunchService()
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()

        XCTAssertFalse(model.canOpenProject(valid.project.id))

        model.updateConnection(connection(identity: .init(version: "0.7.4", protocolVersion: 17)), snapshot: .launchFixture)
        XCTAssertFalse(model.canOpenProject(valid.project.id))

        let remote = BessieProjectMaterializationConnection(
            definition: .init(name: "Remote", kind: .ssh, sshHost: "example", session: "bessie"),
            socketPath: "/tmp/bessie-project-tests.sock",
            generation: connection().generation,
            identity: .init(version: "0.7.5", protocolVersion: 17)
        )
        model.updateConnection(remote, snapshot: .launchFixture)
        XCTAssertFalse(model.canOpenProject(valid.project.id))

        model.updateConnection(connection(), snapshot: .launchFixture)
        XCTAssertTrue(model.canOpenProject(valid.project.id))
        XCTAssertFalse(model.canOpenProject(invalidProject.id))
    }

    func testCommandProjectRequiresReviewBeforeLaunchAndShowsExactFacts() throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Reviewed", command: "swift test --filter Exact"))
        let service = FakeProjectLaunchService()
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)

        let review = try XCTUnwrap(model.launchReview)
        XCTAssertEqual(review.connectionName, "This Mac")
        XCTAssertEqual(review.project.workingDirectory, workingDirectory.resolvingSymlinksInPath().path)
        XCTAssertEqual(review.project.tabs.first?.panes.first?.command, "swift test --filter Exact")
        XCTAssertEqual(service.launchCount, 0)
    }

    func testDesignPreviewLaunchReviewShowsExactCommandWithoutMaterializing() {
        let service = FakeProjectLaunchService()
        let model = ProjectsViewModel(store: makeStore(), launchService: service)
        model.presentDesignPreviewLaunchReview(connectionName: "Local proof")
        XCTAssertEqual(model.launchReview?.connectionName, "Local proof")
        XCTAssertEqual(model.launchReview?.project.name, "Launch review proof")
        XCTAssertEqual(model.launchReview?.project.tabs.first?.panes.first?.command, "printf bessie-project-open-proof")
        XCTAssertEqual(service.launchCount, 0)
        XCTAssertNil(model.opening)
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

    func testPartialFailureSurfacesExactIDsCommandStateAndDisablesUnsafeRetry() async throws {
        let store = makeStore()
        let stored = try store.create(project(name: "Partial", command: "make run"))
        let service = FakeProjectLaunchService()
        service.result = .failure(partialFailure(project: stored.project))
        let model = ProjectsViewModel(store: store, launchService: service)
        model.load()
        model.updateConnection(connection(), snapshot: .launchFixture)

        model.requestOpen(stored.project.id)
        model.confirmLaunch()
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
        let command = BessieKeyboardShortcutRouter.commands.first { $0.command == .projectsPicker }
        let capture = BessieKeyboardShortcutRouter.commands.first { $0.command == .saveCurrentWorkspaceAsProject }
        XCTAssertEqual(command?.title, "Open Projects")
        XCTAssertTrue(command?.matches("project recipes") == true)
        XCTAssertEqual(capture?.title, "Save current workspace as project…")
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

    private func connection(identity: HerdrServerIdentity = .init(version: "0.7.5", protocolVersion: 17))
        -> BessieProjectMaterializationConnection
    {
        BessieProjectMaterializationConnection(
            definition: .localBessie,
            socketPath: "/tmp/bessie-project-tests.sock",
            generation: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            identity: identity
        )
    }

    private func materializationResult(project: BessieProject) -> BessieProjectMaterializationResult {
        let tab = project.tabs[0]
        let pane = tab.panes[0]
        let connection = connection()
        return BessieProjectMaterializationResult(
            plan: .init(project: project, connection: connection),
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

private final class FakeProjectLaunchService: ProjectLaunchServicing, @unchecked Sendable {
    private let lock = NSLock()
    var result: Result<BessieProjectMaterializationResult, BessieProjectMaterializationFailure>?
    var waitForCancellation = false
    private(set) var launchCount = 0
    private(set) var mutationRequestCount = 0

    func materialize(
        _ project: BessieProject,
        on connection: BessieProjectMaterializationConnection,
        onProgress: @escaping @Sendable (BessieProjectMaterializationProgressFact) -> Void
    ) throws -> BessieProjectMaterializationResult {
        lock.withLock { launchCount += 1 }
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
        version: "0.7.5",
        protocolVersion: 17,
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
        version: "0.7.5",
        protocolVersion: 17,
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
        version: "0.7.5", protocolVersion: 17,
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
