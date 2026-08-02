import AppKit
import BessieCore
import SwiftUI

struct ProjectsSurface: View {
    @ObservedObject var model: ProjectsViewModel
    @State private var deleteCandidate: BessieStoredProject?

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: "Projects") {
                captureButton
                Button("New Project") { model.beginCreate() }
                    .buttonStyle(BessiePrimaryButtonStyle())
                    .accessibilityHint("Create a reusable local Project recipe")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(BessieDesign.subtle)
                TextField("Search names, descriptions, groups, folders, and commands", text: $model.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(BessieDesign.inset)
            .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            if model.isLoading {
                ProgressView("Loading Projects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.projects.isEmpty && model.issues.isEmpty {
                emptyState
            } else {
                catalog
            }
        }
        .background(BessieDesign.background)
        .task { model.load() }
        .sheet(item: $model.draft) { _ in ProjectEditorView(model: model) }
        .confirmationDialog(
            "Move Project to Trash?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
            titleVisibility: .visible
        ) {
            if let deleteCandidate {
                Button("Move “\(deleteCandidate.project.name)” to Trash", role: .destructive) {
                    model.delete(deleteCandidate.project.id)
                    self.deleteCandidate = nil
                }
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("The Project recipe moves to Trash. Its folder and any Herdr workspaces are not changed.")
        }
        .alert("Projects", isPresented: messagePresented) {
            Button("OK") { model.clearMessage() }
        } message: { Text(model.errorMessage ?? model.notice ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(BessieDesign.faint)
            Text("Create your first Project")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            Text("Projects are local reusable layouts. They can be authored while Herdr is disconnected.")
                .font(.system(size: 11.5))
                .foregroundStyle(BessieDesign.subtle)
                .multilineTextAlignment(.center)
            Button("New Project") { model.beginCreate() }
                .buttonStyle(BessiePrimaryButtonStyle())
            captureButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var captureButton: some View {
        let unavailableReason = model.captureUnavailableReason
        return Button("Save current workspace as project…") { model.beginCaptureCurrentWorkspace() }
            .buttonStyle(BessieSecondaryButtonStyle())
            .disabled(unavailableReason != nil)
            .help(unavailableReason ?? "Capture the focused Herdr workspace as a new Project draft")
    }

    private var catalog: some View {
        let sections = model.sections
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !model.issues.isEmpty { issuePanel }

                if sections.allSatisfy(\.projects.isEmpty) {
                    Text("No Projects match this search.")
                        .font(.system(size: 12))
                        .foregroundStyle(BessieDesign.subtle)
                        .frame(maxWidth: .infinity, minHeight: 180)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        BessieSectionLabel(section.name)
                        ForEach(section.projects, id: \.sourceURL) { stored in projectRow(stored) }
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
    }

    private var issuePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Catalog issues", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BessieDesign.strong)
            ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.filename)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(BessieDesign.strong)
                        Text(issue.message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                    Spacer()
                    if issue.kind == .filenameMismatch, let id = issue.embeddedProjectID {
                        Button("Recover filename") { model.recoverFilenameMismatch(id) }
                            .buttonStyle(BessieSecondaryButtonStyle())
                    }
                }
            }
        }
        .padding(12)
        .background(BessieDesign.inset)
        .overlay { Rectangle().stroke(BessieDesign.borderStrong, lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    private func projectRow(_ stored: BessieStoredProject) -> some View {
        let project = stored.project
        let paneCount = project.tabs.reduce(0) { $0 + $1.panes.count }
        let commands = project.tabs.flatMap(\.panes).compactMap(\.command).filter { !$0.isEmpty }
        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: project.archivedAt == nil ? "folder" : "archivebox")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(BessieDesign.subtle)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(BessieDesign.strong)
                    if project.archivedAt != nil {
                        Text("ARCHIVED")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                }
                Text(project.workingDirectory)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.subtle)
                    .lineLimit(1)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    Text("\(project.tabs.count) tab\(project.tabs.count == 1 ? "" : "s")")
                    Text("\(paneCount) pane\(paneCount == 1 ? "" : "s")")
                    if model.runningInstance(for: project.id) != nil { Text("Running") }
                    if let command = commands.first {
                        Text(command)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                    } else {
                        Text("Shell only")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(BessieDesign.faint)
            }
            Spacer(minLength: 10)
            Button("Open") { model.requestOpen(project.id) }
                .buttonStyle(BessiePrimaryButtonStyle())
                .disabled(!model.canOpenProject(project.id))
                .help(model.canOpenProject(project.id)
                    ? "Open in \(project.workingDirectory)"
                    : model.openUnavailableReason(for: project.id))
            Button("Edit") { model.beginEdit(stored) }
                .buttonStyle(BessieSecondaryButtonStyle())
            Menu {
                Button("Duplicate") { model.duplicate(project.id) }
                Button(project.archivedAt == nil ? "Archive" : "Unarchive") {
                    model.setArchived(project.archivedAt == nil, projectID: project.id)
                }
                Divider()
                Button("Reveal Project Folder") { reveal(project.workingDirectory) }
                Button("Copy Folder Path") { copy(project.workingDirectory) }
                Divider()
                Button("Delete…", role: .destructive) { deleteCandidate = stored }
            } label: {
                Image(systemName: "ellipsis").frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(project.name)")
        }
        .padding(13)
        .background(BessieDesign.panel)
        .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        .opacity(project.archivedAt == nil ? 1 : 0.7)
        .accessibilityElement(children: .contain)
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path, isDirectory: true)])
    }

    private func copy(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        model.clearMessage()
    }

    private var messagePresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil || model.notice != nil },
            set: { if !$0 { model.clearMessage() } }
        )
    }
}

extension View {
    func projectConnectionSync(
        model: ProjectsViewModel,
        connection: BessieProjectMaterializationConnection?,
        snapshot: HerdrSnapshot
    ) -> some View {
        modifier(ProjectConnectionSyncModifier(model: model, connection: connection, snapshot: snapshot))
    }

    func projectLaunchPresentation(
        model: ProjectsViewModel,
        navigate: @escaping (ProjectWorkspaceHandoff) -> Void
    ) -> some View {
        modifier(ProjectLaunchPresentationModifier(model: model, navigate: navigate))
    }
}

private struct ProjectConnectionSyncModifier: ViewModifier {
    @ObservedObject var model: ProjectsViewModel
    let connection: BessieProjectMaterializationConnection?
    let snapshot: HerdrSnapshot

    func body(content: Content) -> some View {
        content
            .onAppear { model.updateConnection(connection, snapshot: snapshot) }
            .onDisappear { model.updateConnection(nil, snapshot: nil) }
            .onChange(of: connection) { _, connection in
                model.updateConnection(connection, snapshot: snapshot)
            }
            .onChange(of: snapshot) { _, snapshot in
                model.updateConnection(connection, snapshot: snapshot)
            }
    }
}

private struct ProjectLaunchPresentationModifier: ViewModifier {
    @ObservedObject var model: ProjectsViewModel
    let navigate: (ProjectWorkspaceHandoff) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let opening = model.opening {
                    ProjectLaunchProgressCard(model: model, opening: opening).padding(18)
                }
            }
            .sheet(item: reviewBinding) { review in
                ProjectLaunchReviewView(model: model, review: review)
            }
            .sheet(item: failureBinding) { failure in
                ProjectLaunchFailureView(model: model, presentation: failure)
            }
            .onChange(of: model.navigationHandoff) { _, handoff in
                guard let handoff else { return }
                navigate(handoff)
                model.consumeNavigationHandoff()
            }
    }

    private var reviewBinding: Binding<ProjectLaunchReview?> {
        Binding(get: { model.launchReview }, set: { if $0 == nil { model.cancelLaunchReview() } })
    }

    private var failureBinding: Binding<ProjectLaunchFailurePresentation?> {
        Binding(get: { model.launchFailure }, set: { if $0 == nil { model.clearLaunchFailure() } })
    }
}

private struct ProjectLaunchProgressCard: View {
    @ObservedObject var model: ProjectsViewModel
    let opening: ProjectOpeningState

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Opening \(opening.projectName)").font(.system(size: 12, weight: .semibold))
                Text(model.progress.map { projectStageName($0.stage) } ?? "Preparing launch…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.subtle)
            }
            Button("Cancel") { model.cancelLaunch() }.buttonStyle(BessieSecondaryButtonStyle())
        }
        .padding(12)
        .background(BessieDesign.panel)
        .overlay { Rectangle().stroke(BessieDesign.borderStrong, lineWidth: 1) }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
    }
}

private struct ProjectLaunchReviewView: View {
    @ObservedObject var model: ProjectsViewModel
    let review: ProjectLaunchReview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Project launch").font(.system(size: 18, weight: .semibold))
            launchFact("Connection", review.connectionName)
            launchFact("Working directory", review.project.workingDirectory, monospaced: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(review.project.tabs) { tab in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(tab.name).font(.system(size: 12, weight: .semibold))
                            ForEach(tab.panes) { pane in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(pane.label ?? "Shell").font(.system(size: 10.5, weight: .medium))
                                    if let command = pane.command {
                                        Text(command)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .textSelection(.enabled)
                                    } else {
                                        Text("Shell only").font(.system(size: 10.5)).foregroundStyle(BessieDesign.subtle)
                                    }
                                }
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(BessieDesign.inset)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelLaunchReview() }.buttonStyle(BessieSecondaryButtonStyle())
                Button("Confirm and Open") { model.confirmLaunch() }.buttonStyle(BessiePrimaryButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 560, height: 520)
        .background(BessieDesign.background)
        .background(BessieWindowSnapshotProbe(role: "sheet"))
    }

    private func launchFact(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BessieSectionLabel(label)
            Text(value)
                .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
        }
    }
}

private struct ProjectLaunchFailureView: View {
    @ObservedObject var model: ProjectsViewModel
    let presentation: ProjectLaunchFailurePresentation

    var body: some View {
        let partial = presentation.failure.partialResult
        VStack(alignment: .leading, spacing: 14) {
            Text(partial.workspaceID == nil ? "Project did not open" : "Project opened partially")
                .font(.system(size: 18, weight: .semibold))
            Text("Bessie stopped at \(projectStageName(presentation.failure.stage)). Herdr objects that were created remain alive.")
                .font(.system(size: 11.5))
                .foregroundStyle(BessieDesign.subtle)
            failureFact("Owner error", String(describing: presentation.failure.ownerError))
            failureFact("Attempt", String(describing: presentation.failure.attempt))
            failureFact("Workspace ID", partial.workspaceID ?? "Not returned")
            failureFact("Known tab IDs", partial.tabIDsByRecipeID.values.sorted().joined(separator: ", ").nilIfEmpty ?? "None")
            failureFact("Known pane IDs", partial.paneIDsByRecipeID.values.sorted().joined(separator: ", ").nilIfEmpty ?? "None")
            failureFact("Mutation outcome", String(describing: partial.mutationOutcome))
            if !partial.commands.isEmpty {
                BessieSectionLabel("Command attempts")
                ForEach(partial.commands, id: \.recipePaneID) { command in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(command.command).font(.system(size: 10.5, design: .monospaced))
                        Text("ready \(yesNo(command.readinessConfirmed)) · text \(delivery(command, enter: false)) · echo \(yesNo(command.echoConfirmed)) · Enter \(delivery(command, enter: true))")
                            .font(.system(size: 10))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                    .padding(9)
                    .background(BessieDesign.inset)
                }
            }
            Spacer()
            HStack {
                Button("Dismiss") { model.clearLaunchFailure() }.buttonStyle(BessieSecondaryButtonStyle())
                Spacer()
                if model.canOpenPartialWorkspace {
                    Button("Open partial workspace") { model.openPartialWorkspace() }
                        .buttonStyle(BessieSecondaryButtonStyle())
                }
                if model.canRetryLaunchFailure {
                    Button("Retry") { model.retryLaunch() }.buttonStyle(BessiePrimaryButtonStyle())
                }
            }
        }
        .padding(22)
        .frame(width: 620, height: 520)
        .background(BessieDesign.background)
    }

    private func failureFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            BessieSectionLabel(label)
            Text(value).font(.system(size: 10.5, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    private func delivery(_ command: BessieProjectCommandMaterialization, enter: Bool) -> String {
        let acknowledged = enter ? command.enterSubmitted : command.textSubmitted
        if acknowledged { return "acknowledged" }
        guard presentation.failure.partialResult.mutationOutcome == .outcomeUnknown,
              presentation.failure.attempt == .command(paneID: command.recipePaneID)
        else { return "not attempted" }
        if enter, presentation.failure.stage == .submittingCommandEnter { return "outcome unknown" }
        if !enter, presentation.failure.stage == .submittingCommandText { return "outcome unknown" }
        return "not attempted"
    }
}

private func projectStageName(_ stage: BessieProjectMaterializationStage) -> String {
    stage.rawValue.reduce(into: "") { result, character in
        if character.isUppercase { result.append(" ") }
        result.append(character.lowercased())
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
