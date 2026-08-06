import BessieCore
import Foundation
import SwiftUI

struct ProjectCatalogSection: Identifiable, Equatable {
    let projects: [BessieStoredProject]
    let id = "projects"
    let name = "Projects"
}

struct BessieProjectDraft: Identifiable {
    var project: BessieProject
    let revision: BessieProjectRevision?

    var id: UUID { project.id }
    var name: String {
        get { project.name }
        set { project.name = newValue }
    }
    var projectDescription: String {
        get { project.projectDescription }
        set { project.projectDescription = newValue }
    }
    var workingDirectory: String {
        get { project.workingDirectory }
        set { project.workingDirectory = newValue }
    }
    var folders: [BessieProjectFolder] {
        get { project.folders }
        set { project.folders = newValue }
    }
    var tabs: [BessieProjectTab] {
        get { project.tabs }
        set { project.tabs = newValue }
    }
}

struct ProjectLaunchReviewPresentation: Identifiable, Equatable {
    let project: BessieProject
    let connectionLabel: String

    var id: UUID { project.id }
}

@MainActor
final class ProjectsViewModel: ObservableObject {
    @Published private(set) var projects: [BessieStoredProject] = []
    @Published private(set) var issues: [BessieProjectCatalogIssue] = []
    @Published private(set) var isLoading = false
    @Published var searchQuery = ""
    @Published var draft: BessieProjectDraft?
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var conflict: BessieProjectWriteConflict?
    @Published private(set) var opening: ProjectOpeningState?
    @Published private(set) var progress: BessieProjectMaterializationProgressFact?
    @Published private(set) var launchReview: ProjectLaunchReviewPresentation?
    @Published private(set) var launchFailure: ProjectLaunchFailurePresentation?
    @Published private(set) var navigationHandoff: ProjectWorkspaceHandoff?

    private let store: BessieProjectStore
    private let launchService: any ProjectLaunchServicing
    private var connection: BessieProjectMaterializationConnection?
    private var connectionSnapshot: HerdrSnapshot?
    private var launchTask: Task<Void, Never>?
    private var runningInstances: [BessieProjectRunningInstance] = []

    init(
        store: BessieProjectStore = BessieProjectStore(),
        launchService: any ProjectLaunchServicing = LiveProjectLaunchService()
    ) {
        self.store = store
        self.launchService = launchService
    }

    var storeRoot: URL { store.rootURL }

    var canCaptureCurrentWorkspace: Bool { captureUnavailableReason == nil }

    var captureUnavailableReason: String? {
        guard connection != nil else { return "Connect to Herdr before saving a workspace as a Project." }
        guard let connectionSnapshot else { return "No current Herdr workspace snapshot is available." }
        do {
            try BessieProjectCapture.validate(HerdrSessionProjection(snapshot: connectionSnapshot))
            return nil
        } catch {
            return Self.captureMessage(for: error)
        }
    }

    var filteredProjects: [BessieStoredProject] {
        let terms = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return projects }
        return projects.filter { stored in
            let project = stored.project
            let commands = project.tabs.flatMap(\.panes).compactMap(\.command).joined(separator: " ")
            let haystack = [
                project.name, project.projectDescription,
                project.folders.flatMap { [$0.name, $0.path] }.joined(separator: " "), commands,
            ].joined(separator: " ").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    var sections: [ProjectCatalogSection] {
        [ProjectCatalogSection(projects: filteredProjects)]
    }

    var validationMessages: [String] {
        guard let draft else { return [] }
        do {
            _ = try draft.project.normalized()
            return []
        } catch let error as BessieProjectValidationError {
            return error.issues.map(Self.message(for:))
        } catch {
            return [error.localizedDescription]
        }
    }

    func load() {
        isLoading = true
        defer { isLoading = false }
        do {
            let catalog = try store.list()
            projects = catalog.projects
            issues = catalog.issues
            errorMessage = nil
        } catch {
            errorMessage = "Projects could not be loaded: \(error.localizedDescription)"
        }
    }

    func beginCreate(workingDirectory: String = "") {
        let rootPane = BessieProjectPane(label: "Shell", placement: .root)
        let project = BessieProject(
            name: "Untitled project",
            workingDirectory: workingDirectory,
            tabs: [BessieProjectTab(name: "Main", panes: [rootPane])]
        )
        conflict = nil
        errorMessage = nil
        draft = BessieProjectDraft(project: project, revision: nil)
    }

    func beginEdit(_ stored: BessieStoredProject) {
        conflict = nil
        errorMessage = nil
        draft = BessieProjectDraft(project: stored.project, revision: stored.revision)
    }

    @discardableResult
    func beginCaptureCurrentWorkspace() -> Bool {
        guard canCaptureCurrentWorkspace, let connectionSnapshot else {
            notice = captureUnavailableReason
            return false
        }
        do {
            let project = try BessieProjectCapture.capture(
                from: HerdrSessionProjection(snapshot: connectionSnapshot)
            )
            conflict = nil
            errorMessage = nil
            notice = nil
            draft = BessieProjectDraft(project: project, revision: nil)
            return true
        } catch {
            notice = Self.captureMessage(for: error)
            return false
        }
    }

    func reportCaptureUnavailable(_ reason: String) {
        notice = reason
    }

    func discardDraft() {
        draft = nil
        conflict = nil
        errorMessage = nil
    }

    @discardableResult
    func saveDraft() -> Bool {
        guard let draft else { return false }
        let validation = validationMessages
        guard validation.isEmpty else {
            errorMessage = validation.joined(separator: " ")
            return false
        }
        do {
            _ = try store.save(draft.project, expected: draft.revision)
            self.draft = nil
            conflict = nil
            notice = draft.revision == nil ? "Project created." : "Project saved."
            load()
            return true
        } catch let BessieProjectStoreError.staleWrite(writeConflict) {
            conflict = writeConflict
            errorMessage = "This project changed on disk. Your draft is preserved; reload or reconcile before saving."
            return false
        } catch {
            errorMessage = "Project could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func duplicate(_ projectID: UUID) {
        guard let stored = projects.first(where: { $0.project.id == projectID }) else { return }
        perform("Project could not be duplicated") { _ = try store.duplicate(stored) }
    }

    func setArchived(_ archived: Bool, projectID: UUID) {
        guard let stored = projects.first(where: { $0.project.id == projectID }) else { return }
        perform(archived ? "Project could not be archived" : "Project could not be unarchived") {
            _ = try store.setArchived(archived, project: stored)
        }
    }

    func delete(_ projectID: UUID) {
        guard let stored = projects.first(where: { $0.project.id == projectID }) else { return }
        perform("Project could not be moved to Trash") { try store.delete(stored) }
    }

    func recoverFilenameMismatch(_ projectID: UUID) {
        guard let stored = projects.first(where: { $0.project.id == projectID && $0.filenameMismatch }) else { return }
        perform("Filename could not be recovered") { _ = try store.recoverFilenameMismatch(stored) }
    }

    func updateConnection(
        _ connection: BessieProjectMaterializationConnection?,
        snapshot: HerdrSnapshot?
    ) {
        if self.connection != connection {
            launchTask?.cancel()
            launchReview = nil
            navigationHandoff = nil
        }
        self.connection = connection
        connectionSnapshot = connection == nil ? nil : snapshot
        launchService.updateConnection(connection)
        revalidateRunningInstances()
    }

    func canOpenProject(_ projectID: UUID) -> Bool {
        guard opening == nil,
              let connection,
              connection.definition.kind == .local,
              HerdrCompatibility.incompatibility(for: connection.identity) == nil,
              let project = projects.first(where: { $0.project.id == projectID })?.project
        else { return false }
        return (try? project.normalized()) != nil
    }

    func openUnavailableReason(for projectID: UUID) -> String {
        guard opening == nil else { return "Another Project is opening." }
        guard let connection else { return "Connect to compatible local Herdr before opening this Project." }
        guard connection.definition.kind == .local else { return "Remote Project opening is not supported in V1." }
        if let reason = HerdrCompatibility.incompatibility(for: connection.identity) { return reason }
        guard let project = projects.first(where: { $0.project.id == projectID })?.project,
              (try? project.normalized()) != nil
        else { return "Fix the Project validation errors before opening it." }
        return "This Project cannot be opened right now."
    }

    func requestOpen(_ projectID: UUID) {
        guard canOpenProject(projectID),
              let stored = projects.first(where: { $0.project.id == projectID }),
              let connection
        else {
            notice = openUnavailableReason(for: projectID)
            return
        }
        let project = (try? stored.project.normalized()) ?? stored.project
        if project.tabs.flatMap(\.panes).contains(where: { $0.command != nil }) {
            launchReview = ProjectLaunchReviewPresentation(
                project: project,
                connectionLabel: connection.definition.name
            )
        } else {
            beginLaunch(project, connection: connection)
        }
    }

    func confirmLaunchReview() {
        guard let review = launchReview,
              canOpenProject(review.project.id),
              let connection
        else {
            launchReview = nil
            return
        }
        launchReview = nil
        beginLaunch(review.project, connection: connection)
    }

    func cancelLaunchReview() {
        launchReview = nil
    }

    func cancelLaunch() {
        launchTask?.cancel()
    }

    func retryLaunch() {
        guard canRetryLaunchFailure, let projectID = launchFailure?.project.id else { return }
        launchFailure = nil
        requestOpen(projectID)
    }

    func openPartialWorkspace() {
        guard let presentation = launchFailure,
              let connection,
              failureMatchesCurrentConnection(presentation.failure),
              let handoff = Self.handoff(
                project: presentation.project,
                connection: connection,
                workspaceID: presentation.failure.partialResult.workspaceID,
                tabIDs: presentation.failure.partialResult.tabIDsByRecipeID,
                paneIDs: presentation.failure.partialResult.paneIDsByRecipeID,
                snapshot: connectionSnapshot
              )
        else { return }
        navigationHandoff = handoff
    }

    func clearLaunchFailure() { launchFailure = nil }

    func consumeNavigationHandoff() { navigationHandoff = nil }

    func isOpening(_ projectID: UUID) -> Bool { opening?.projectID == projectID }

    func runningInstance(for projectID: UUID) -> BessieProjectRunningInstance? {
        runningInstances.first { $0.projectID == projectID }
    }

    func openRunningWorkspace(_ projectID: UUID) {
        guard let project = projects.first(where: { $0.project.id == projectID })?.project,
              let connection,
              let snapshot = connectionSnapshot,
              let running = runningInstance(for: projectID),
              running.connectionID == connection.definition.id,
              running.socketPath == connection.socketPath,
              running.generation == connection.generation,
              let handoff = Self.handoff(
                project: project,
                connection: connection,
                workspaceID: running.workspaceID,
                tabIDs: running.tabIDsByRecipeID,
                paneIDs: running.paneIDsByRecipeID,
                snapshot: snapshot
              )
        else { return }
        navigationHandoff = handoff
    }

    var canRetryLaunchFailure: Bool {
        guard let presentation = launchFailure else { return false }
        return presentation.canRetry && failureMatchesCurrentConnection(presentation.failure)
    }

    var canOpenPartialWorkspace: Bool {
        guard let presentation = launchFailure,
              presentation.failure.partialResult.workspaceID != nil,
              failureMatchesCurrentConnection(presentation.failure)
        else { return false }
        return Self.handoff(
            project: presentation.project,
            connection: connection!,
            workspaceID: presentation.failure.partialResult.workspaceID,
            tabIDs: presentation.failure.partialResult.tabIDsByRecipeID,
            paneIDs: presentation.failure.partialResult.paneIDsByRecipeID,
            snapshot: connectionSnapshot
        ) != nil
    }

    func clearMessage() {
        errorMessage = nil
        notice = nil
    }

    func addTab() {
        guard var draft else { return }
        let count = draft.tabs.count + 1
        draft.tabs.append(BessieProjectTab(
            name: "Tab \(count)",
            panes: [BessieProjectPane(label: "Shell", placement: .root)]
        ))
        self.draft = draft
    }

    func addFolders(_ urls: [URL]) {
        guard var draft else { return }
        for url in urls {
            let path = url.standardizedFileURL.path
            let name = url.lastPathComponent.isEmpty ? "Folder" : url.lastPathComponent
            draft.folders.append(.init(name: name, path: path))
        }
        self.draft = draft
    }

    func renameFolder(_ folderID: UUID, name: String) {
        guard var draft, let index = draft.folders.firstIndex(where: { $0.id == folderID }) else { return }
        draft.folders[index].name = name
        self.draft = draft
    }

    func updateFolderPath(_ folderID: UUID, path: String) {
        guard var draft, let index = draft.folders.firstIndex(where: { $0.id == folderID }) else { return }
        draft.folders[index].path = path
        self.draft = draft
    }

    func moveFolder(_ folderID: UUID, by offset: Int) {
        guard var draft, let source = draft.folders.firstIndex(where: { $0.id == folderID }) else { return }
        let destination = max(0, min(draft.folders.count - 1, source + offset))
        guard source != destination else { return }
        let folder = draft.folders.remove(at: source)
        draft.folders.insert(folder, at: destination)
        self.draft = draft
    }

    func makePrimaryFolder(_ folderID: UUID) {
        guard var draft, draft.folders.contains(where: { $0.id == folderID }) else { return }
        for index in draft.folders.indices {
            draft.folders[index].isPrimary = draft.folders[index].id == folderID
        }
        self.draft = draft
    }

    func removeFolder(_ folderID: UUID) {
        guard var draft, draft.folders.count > 1,
              let removed = draft.folders.first(where: { $0.id == folderID })
        else { return }
        draft.folders.removeAll { $0.id == folderID }
        if removed.isPrimary, let firstID = draft.folders.first?.id {
            for index in draft.folders.indices {
                draft.folders[index].isPrimary = draft.folders[index].id == firstID
            }
        }
        for tabIndex in draft.tabs.indices {
            for paneIndex in draft.tabs[tabIndex].panes.indices where
                draft.tabs[tabIndex].panes[paneIndex].folderID == folderID
            {
                draft.tabs[tabIndex].panes[paneIndex].folderID = nil
            }
        }
        self.draft = draft
    }

    func renameTab(_ tabID: UUID, name: String) {
        guard var draft, let index = draft.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        draft.tabs[index].name = name
        self.draft = draft
    }

    func moveTab(_ tabID: UUID, by offset: Int) {
        guard var draft, let source = draft.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let destination = max(0, min(draft.tabs.count - 1, source + offset))
        guard source != destination else { return }
        let tab = draft.tabs.remove(at: source)
        draft.tabs.insert(tab, at: destination)
        self.draft = draft
    }

    func duplicateTab(_ tabID: UUID) {
        guard var draft, let index = draft.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        let source = draft.tabs[index]
        var paneIDs: [UUID: UUID] = [:]
        for pane in source.panes { paneIDs[pane.id] = UUID() }
        let panes = source.panes.map { pane -> BessieProjectPane in
            let placement: BessieProjectPanePlacement
            switch pane.placement {
            case .root:
                placement = .root
            case .split(let parentID, let direction, let ratio):
                placement = .split(fromPaneID: paneIDs[parentID]!, direction: direction, ratio: ratio)
            }
            return BessieProjectPane(
                id: paneIDs[pane.id]!, label: pane.label, command: pane.command,
                folderID: pane.folderID, placement: placement
            )
        }
        let copy = BessieProjectTab(id: UUID(), name: "\(source.name) copy", panes: panes)
        draft.tabs.insert(copy, at: index + 1)
        self.draft = draft
    }

    func removeTab(_ tabID: UUID) {
        guard var draft, draft.tabs.count > 1 else { return }
        draft.tabs.removeAll { $0.id == tabID }
        self.draft = draft
    }

    func addPane(tabID: UUID, from paneID: UUID, direction: SplitDirection) {
        guard var draft,
              let tabIndex = draft.tabs.firstIndex(where: { $0.id == tabID }),
              draft.tabs[tabIndex].panes.contains(where: { $0.id == paneID })
        else { return }
        draft.tabs[tabIndex].panes.append(BessieProjectPane(
            label: "Shell",
            placement: .split(fromPaneID: paneID, direction: direction, ratio: 0.5)
        ))
        self.draft = draft
    }

    func updatePaneLabel(tabID: UUID, paneID: UUID, label: String?) {
        mutatePane(tabID: tabID, paneID: paneID) { $0.label = label }
    }

    func updatePaneCommand(tabID: UUID, paneID: UUID, command: String?) {
        mutatePane(tabID: tabID, paneID: paneID) { $0.command = command?.isEmpty == true ? nil : command }
    }

    func updatePaneFolder(tabID: UUID, paneID: UUID, folderID: UUID?) {
        mutatePane(tabID: tabID, paneID: paneID) { $0.folderID = folderID }
    }

    func updatePaneRatio(tabID: UUID, paneID: UUID, ratio: Double) {
        mutatePane(tabID: tabID, paneID: paneID) { pane in
            guard case .split(let parentID, let direction, _) = pane.placement else { return }
            pane.placement = .split(fromPaneID: parentID, direction: direction, ratio: ratio)
        }
    }

    func removePane(tabID: UUID, paneID: UUID) {
        guard var draft,
              let tabIndex = draft.tabs.firstIndex(where: { $0.id == tabID }),
              draft.tabs[tabIndex].panes.count > 1,
              !draft.tabs[tabIndex].panes.contains(where: { pane in
                  if case .split(let parentID, _, _) = pane.placement { return parentID == paneID }
                  return false
              })
        else { return }
        draft.tabs[tabIndex].panes.removeAll { $0.id == paneID }
        self.draft = draft
    }

    func canRemovePane(tabID: UUID, paneID: UUID) -> Bool {
        guard let tab = draft?.tabs.first(where: { $0.id == tabID }), tab.panes.count > 1 else { return false }
        return !tab.panes.contains { pane in
            if case .split(let parentID, _, _) = pane.placement { return parentID == paneID }
            return false
        }
    }

    private func perform(_ failurePrefix: String, operation: () throws -> Void) {
        do {
            try operation()
            errorMessage = nil
            load()
        } catch {
            errorMessage = "\(failurePrefix): \(error.localizedDescription)"
        }
    }

    private func beginLaunch(
        _ project: BessieProject,
        connection: BessieProjectMaterializationConnection
    ) {
        guard opening == nil, self.connection == connection else { return }
        launchFailure = nil
        navigationHandoff = nil
        progress = nil
        opening = ProjectOpeningState(projectID: project.id, projectName: project.name)
        let service = launchService
        let progressSink = ProjectLaunchProgressSink { [weak self] fact in
            guard self?.connection == connection, self?.opening?.projectID == project.id else { return }
            self?.progress = fact
        }
        launchTask = Task.detached { [weak self] in
            do {
                let result = try service.materialize(project, on: connection) { fact in
                    progressSink.send(fact)
                }
                await MainActor.run { [weak self] in self?.completeLaunch(result) }
            } catch let failure as BessieProjectMaterializationFailure {
                await MainActor.run { [weak self] in self?.failLaunch(project: project, failure: failure) }
            } catch {
                let failure = BessieProjectMaterializationFailure(
                    stage: .validatingProject,
                    attempt: .project(project.id),
                    ownerError: .unexpected(error.localizedDescription),
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
                await MainActor.run { [weak self] in self?.failLaunch(project: project, failure: failure) }
            }
        }
    }

    private func completeLaunch(_ result: BessieProjectMaterializationResult) {
        guard connection == result.plan.connection else { return }
        opening = nil
        launchTask = nil
        connectionSnapshot = result.finalSnapshot
        let record = BessieProjectRunningInstance(
            projectID: result.plan.project.id,
            connectionID: result.plan.connection.definition.id,
            socketPath: result.plan.connection.socketPath,
            generation: result.plan.connection.generation,
            workspaceID: result.workspaceID,
            tabIDsByRecipeID: result.tabIDsByRecipeID,
            paneIDsByRecipeID: result.paneIDsByRecipeID
        )
        runningInstances.removeAll {
            $0.projectID == record.projectID
                && $0.connectionID == record.connectionID
                && $0.socketPath == record.socketPath
                && $0.generation == record.generation
                && $0.workspaceID == record.workspaceID
        }
        runningInstances.append(record)
        navigationHandoff = Self.handoff(
            project: result.plan.project,
            connection: result.plan.connection,
            workspaceID: result.workspaceID,
            tabIDs: result.tabIDsByRecipeID,
            paneIDs: result.paneIDsByRecipeID,
            snapshot: result.finalSnapshot
        )
        notice = "\(result.plan.project.name) opened in Herdr."
    }

    private func failLaunch(project: BessieProject, failure: BessieProjectMaterializationFailure) {
        guard opening?.projectID == project.id else { return }
        opening = nil
        launchTask = nil
        let safeRetry = failure.partialResult.workspaceID == nil
            && failure.partialResult.mutationOutcome == .notAttempted
            && connection?.definition.id == failure.partialResult.connectionID
            && connection?.socketPath == failure.partialResult.socketPath
            && connection?.generation == failure.partialResult.generation
        launchFailure = ProjectLaunchFailurePresentation(project: project, failure: failure, canRetry: safeRetry)
        if let connection {
            if failureMatchesCurrentConnection(failure), let freshSnapshot = failure.partialResult.freshSnapshot {
                connectionSnapshot = freshSnapshot
            }
            navigationHandoff = Self.handoff(
                project: project,
                connection: connection,
                workspaceID: failure.partialResult.workspaceID,
                tabIDs: failure.partialResult.tabIDsByRecipeID,
                paneIDs: failure.partialResult.paneIDsByRecipeID,
                snapshot: failureMatchesCurrentConnection(failure) ? connectionSnapshot : nil
            )
        }
    }

    private func failureMatchesCurrentConnection(_ failure: BessieProjectMaterializationFailure) -> Bool {
        guard let connection else { return false }
        return connection.definition.id == failure.partialResult.connectionID
            && connection.socketPath == failure.partialResult.socketPath
            && connection.generation == failure.partialResult.generation
    }

    private func revalidateRunningInstances() {
        guard let connection, let snapshot = connectionSnapshot else {
            runningInstances.removeAll()
            return
        }
        runningInstances = runningInstances.filter { record in
            guard record.connectionID == connection.definition.id,
                  record.socketPath == connection.socketPath,
                  record.generation == connection.generation,
                  snapshot.workspaces.contains(where: { $0.projectString("workspace_id") == record.workspaceID })
            else { return false }
            return record.tabIDsByRecipeID.values.allSatisfy { runtimeTabID in
                snapshot.tabs.contains {
                    $0.projectString("tab_id") == runtimeTabID
                        && $0.projectString("workspace_id") == record.workspaceID
                }
            } && record.paneIDsByRecipeID.values.allSatisfy { runtimePaneID in
                snapshot.panes.contains {
                    $0.projectString("pane_id") == runtimePaneID
                        && $0.projectString("workspace_id") == record.workspaceID
                }
            }
        }
    }

    private static func handoff(
        project: BessieProject,
        connection: BessieProjectMaterializationConnection,
        workspaceID: String?,
        tabIDs: [UUID: String],
        paneIDs: [UUID: String],
        snapshot: HerdrSnapshot?
    ) -> ProjectWorkspaceHandoff? {
        guard let workspaceID, let snapshot,
              snapshot.workspaces.contains(where: { $0.projectString("workspace_id") == workspaceID })
        else { return nil }
        let recipeTab = project.tabs.first { tab in
            guard let runtimeID = tabIDs[tab.id] else { return false }
            return snapshot.tabs.contains {
                $0.projectString("tab_id") == runtimeID && $0.projectString("workspace_id") == workspaceID
            }
        }
        let tabID = recipeTab.flatMap { tabIDs[$0.id] }
        let paneID = recipeTab?.panes.compactMap { pane -> String? in
            guard let runtimeID = paneIDs[pane.id] else { return nil }
            return snapshot.panes.contains {
                $0.projectString("pane_id") == runtimeID
                    && $0.projectString("workspace_id") == workspaceID
                    && (tabID == nil || $0.projectString("tab_id") == tabID)
            } ? runtimeID : nil
        }.first
        return ProjectWorkspaceHandoff(
            connection: connection,
            workspaceID: workspaceID,
            tabID: tabID,
            paneID: paneID,
            snapshot: snapshot
        )
    }

    private func mutatePane(
        tabID: UUID,
        paneID: UUID,
        mutation: (inout BessieProjectPane) -> Void
    ) {
        guard var draft,
              let tabIndex = draft.tabs.firstIndex(where: { $0.id == tabID }),
              let paneIndex = draft.tabs[tabIndex].panes.firstIndex(where: { $0.id == paneID })
        else { return }
        let original = draft.tabs[tabIndex].panes[paneIndex]
        mutation(&draft.tabs[tabIndex].panes[paneIndex])
        guard draft.tabs[tabIndex].panes[paneIndex] != original else { return }
        self.draft = draft
    }

    private static func message(for issue: BessieProjectValidationIssue) -> String {
        switch issue.code {
        case .unsupportedSchemaVersion: "This Project uses an unsupported schema version."
        case .emptyName: issue.tabID == nil ? "Project name is required." : "Every tab needs a name."
        case .invalidPrimaryFolderCount: "Choose exactly one primary folder."
        case .emptyFolderName: "Every folder needs a display name."
        case .duplicateFolderID: "The draft contains duplicate folder identifiers."
        case .duplicateFolderPath: "Each Project folder must be unique."
        case .folderNotAbsolute, .workingDirectoryNotAbsolute: "Choose absolute Project folders."
        case .folderNotDirectory, .workingDirectoryNotDirectory: "Every Project folder must exist and be a directory."
        case .folderInaccessible: "A Project folder is not accessible. Check its permissions."
        case .paneFolderMissing: "A pane refers to a folder that is no longer in this Project."
        case .missingTabs: "Add at least one tab."
        case .missingPanes: "Every tab needs at least one pane."
        case .duplicateTabID, .duplicatePaneID: "The draft contains duplicate internal identifiers."
        case .invalidRootCount: "Every tab needs exactly one root pane."
        case .splitParentMissing, .splitParentCrossTab, .splitParentNotEarlier, .splitCycle:
            "The pane layout contains an invalid split."
        case .invalidSplitRatio: "Split ratios must be between 10% and 90%."
        case .commandContainsLineBreak: "Startup commands must be a single line."
        }
    }

    private static func captureMessage(for error: Error) -> String {
        if error as? BessieProjectCaptureError == .missingFocusedWorkspace {
            return "Focus a Herdr workspace before saving it as a Project."
        }
        return "The focused workspace does not have a complete capturable layout."
    }
}

private extension JSONValue {
    func projectString(_ key: String) -> String? {
        guard case .object(let object) = self, case .string(let value) = object[key] else { return nil }
        return value
    }
}
