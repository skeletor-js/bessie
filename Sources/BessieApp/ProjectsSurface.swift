import AppKit
import BessieCore
import SwiftUI

struct ProjectsSurface: View {
    @ObservedObject var model: ProjectsViewModel
    @State private var deleteCandidate: BessieStoredProject?

    var body: some View {
        ProjectModeRegion(mode: model.draft != nil) {
            if model.draft != nil {
                ProjectEditorView(model: model)
            } else {
                projectsList
            }
        }
        .task { model.load() }
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

    private var projectsList: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: "Projects") {
                Button { model.beginCreate() } label: {
                    HStack(spacing: 6) {
                        BessieIconView(icon: .plus, size: 13)
                        Text("New project")
                    }
                }
                    .buttonStyle(BessiePrimaryButtonStyle())
                    .accessibilityHint("Create a reusable local Project recipe")
            }

            if model.isLoading {
                ProgressView("Loading Projects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.projects.isEmpty && model.issues.isEmpty {
                emptyState
            } else {
                catalog
            }
        }
    }

    private var emptyState: some View {
        ProductEmptyState(
            symbol: "folder.badge.plus",
            title: "No projects yet",
            detail: "Projects are launch recipes. They remember tabs, panes, folders, and commands without becoming live workspaces.",
            actionTitle: "New project",
            action: { model.beginCreate() }
        )
        .padding(.horizontal, 44)
        .padding(.top, 34)
    }

    private var catalog: some View {
        let sections = model.sections
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !model.issues.isEmpty { issuePanel }

                if sections.allSatisfy(\.projects.isEmpty) {
                    VStack(spacing: 5) {
                        Text("No projects match this search.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BessieDesign.strong)
                        Text("Change or clear the search to see other projects.")
                            .font(.system(size: 11))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        BessieSectionLabel(section.name)
                        ForEach(section.projects, id: \.sourceURL) { stored in projectRow(stored) }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 26)
            .padding(.bottom, 60)
        }
    }

    private var issuePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Catalog issues")
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
        return HStack(alignment: .center, spacing: 13) {
            BessieIconView(icon: .stack, size: 17)
                .foregroundStyle(BessieDesign.subtle)
                .frame(width: 30, height: 30)
                .background(BessieDesign.inset)
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(BessieDesign.strong)
                    if project.archivedAt != nil {
                        Text("Archived")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BessieDesign.subtle)
                    }
                    if model.runningInstance(for: project.id) != nil {
                        Text("running now")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(BessieDesign.strong)
                            .padding(.horizontal, 7)
                            .frame(height: 20)
                            .background(BessieDesign.selected)
                            .clipShape(Capsule())
                    }
                }
                Text(projectSubtitle(project))
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Button(model.isOpening(project.id) ? "Launching…" : "Launch") { model.requestOpen(project.id) }
                .buttonStyle(BessiePrimaryButtonStyle())
                .disabled(!model.canOpenProject(project.id))
                .help(model.canOpenProject(project.id)
                    ? "Launch in \(project.workingDirectory)"
                    : model.openUnavailableReason(for: project.id))
            Menu {
                if model.runningInstance(for: project.id) != nil {
                    Button("Open running workspace") { model.openRunningWorkspace(project.id) }
                    Divider()
                }
                Button("Open editor") { model.beginEdit(stored) }
                Button("Duplicate") { model.duplicate(project.id) }
                Button("Delete", role: .destructive) { deleteCandidate = stored }
            } label: {
                BessieIconView(icon: .dotsThree, size: 15).frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(project.name)")
        }
        .padding(13)
        .background(BessieDesign.panel)
        .overlay {
            RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                .stroke(BessieDesign.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
        .opacity(project.archivedAt == nil ? 1 : 0.7)
        .contentShape(Rectangle())
        .onTapGesture { model.beginEdit(stored) }
        .focusable()
        .onKeyPress(phases: .down) { press in
            guard press.key == .return || press.key == .space else { return .ignored }
            model.beginEdit(stored)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(project.name), \(projectSubtitle(project))")
        .accessibilityHint("Open the Project editor")
        .accessibilityAction(named: "Open editor") { model.beginEdit(stored) }
    }

    private func projectSubtitle(_ project: BessieProject) -> String {
        let workspace = project.primaryFolder.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "workspace"
        let tabs = project.tabs.map(\.name).joined(separator: ", ")
        return tabs.isEmpty ? workspace : "\(workspace) · \(tabs)"
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
        fleet: ConnectionFleetViewModel
    ) -> some View {
        modifier(ProjectConnectionSyncModifier(model: model, fleet: fleet))
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
    @ObservedObject var fleet: ConnectionFleetViewModel
    @EnvironmentObject private var settings: BessieSettingsModel

    func body(content: Content) -> some View {
        content
            .onAppear {
                model.configureLaunchTargetReadiness(
                    resolve: { [weak fleet] connectionID in
                        guard let fleet else {
                            throw ProjectLaunchTargetReadinessError.notConfigured(
                                connectionID: connectionID
                            )
                        }
                        return try await fleet.waitForProjectLaunchTarget(
                            connectionID: connectionID
                        )
                    },
                    reportFailure: { [weak fleet] message in
                        fleet?.reportRouteFailure(message)
                    }
                )
                synchronize()
            }
            .onReceive(fleet.objectWillChange) { _ in
                Task { @MainActor in
                    await Task.yield()
                    synchronize()
                }
            }
            .onReceive(settings.objectWillChange) { _ in
                Task { @MainActor in
                    await Task.yield()
                    synchronize()
                }
            }
    }

    private func synchronize() {
        model.updateConnections(
            definitions: settings.connections,
            targets: fleet.projectLaunchTargets,
            activeConnectionID: fleet.activeConnectionID,
            defaultProjectConnectionID: settings.defaultProjectConnectionID
        )
    }
}

private struct ProjectLaunchPresentationModifier: ViewModifier {
    @ObservedObject var model: ProjectsViewModel
    let navigate: (ProjectWorkspaceHandoff) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if let opening = model.opening {
                    ProjectLaunchEntrance(initialOffset: 10) {
                        ProjectLaunchProgressCard(model: model, opening: opening)
                    }
                    .id(opening.projectID)
                    .padding(18)
                }
            }
            .sheet(item: reviewBinding) { review in
                ProjectLaunchReviewView(model: model, presentation: review)
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

    private var failureBinding: Binding<ProjectLaunchFailurePresentation?> {
        Binding(get: { model.launchFailure }, set: { if $0 == nil { model.clearLaunchFailure() } })
    }

    private var reviewBinding: Binding<ProjectLaunchReviewPresentation?> {
        Binding(get: { model.launchReview }, set: { if $0 == nil { model.cancelLaunchReview() } })
    }
}

private struct ProjectLaunchReviewView: View {
    @ObservedObject var model: ProjectsViewModel
    let presentation: ProjectLaunchReviewPresentation

    private struct CommandRow: Identifiable {
        let id: UUID
        let location: String
        let command: String
    }

    private var commands: [CommandRow] {
        presentation.project.tabs.flatMap { tab in
            tab.panes.compactMap { pane in
                pane.command.map {
                    CommandRow(
                        id: pane.id,
                        location: "\(tab.name) / \(pane.label ?? "Shell")",
                        command: $0
                    )
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Review project launch")
                    .font(.system(size: 20, weight: .semibold))
                Text("Bessie will create ordinary Herdr tabs and panes, then submit these exact commands.")
                    .font(.system(size: 12))
                    .foregroundStyle(BessieDesign.subtle)
            }

            VStack(alignment: .leading, spacing: 7) {
                reviewFact("Project", presentation.project.name)
                reviewFact("Herd", presentation.connectionLabel)
                reviewFact("Folder", presentation.project.workingDirectory)
                reviewFact(
                    "Layout",
                    "\(presentation.project.tabs.count) tabs · \(presentation.project.tabs.flatMap(\.panes).count) panes"
                )
            }

            Text("Startup commands")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(BessieDesign.faint)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(commands) { item in
                        commandRow(item)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { model.cancelLaunchReview() }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Open project") { model.confirmLaunchReview() }
                    .buttonStyle(BessiePrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 500)
        .background(BessieDesign.panel)
        .background(BessieWindowSnapshotProbe(role: "sheet"))
        .accessibilityElement(children: .contain)
    }

    private func reviewFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(BessieDesign.faint)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func commandRow(_ item: CommandRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.location)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(BessieDesign.subtle)
            Text(item.command)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(BessieDesign.background)
        .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Opening \(opening.projectName)")
        .accessibilityValue(model.progress.map { projectStageName($0.stage) } ?? "Preparing launch")
        .onAppear {
            announceProjectLaunch("Opening \(opening.projectName)")
        }
        .onChange(of: model.progress?.stage) { _, stage in
            guard let stage else { return }
            announceProjectLaunch(projectStageName(stage))
        }
    }
}

private struct ProjectModeRegion<Content: View>: View {
    let mode: Bool
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 1.0

    init(mode: Bool, @ViewBuilder content: () -> Content) {
        self.mode = mode
        self.content = content()
    }

    var body: some View {
        content
            .id(mode)
            .opacity(reduceMotion ? 1 : opacity)
            .onChange(of: mode) { _, _ in
                guard !reduceMotion else {
                    opacity = 1
                    return
                }
                opacity = 0
                Task { @MainActor in
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(BessieDesign.motionStrongEaseOut) {
                        opacity = 1
                    }
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    opacity = 1
                }
            }
    }
}

private struct ProjectLaunchEntrance<Content: View>: View {
    let initialOffset: CGFloat
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    @State private var verticalOffset: CGFloat

    init(initialOffset: CGFloat, @ViewBuilder content: () -> Content) {
        self.initialOffset = initialOffset
        self.content = content()
        _verticalOffset = State(initialValue: initialOffset)
    }

    var body: some View {
        content
            .opacity(reduceMotion ? 1 : opacity)
            .offset(y: reduceMotion ? 0 : verticalOffset)
            .task {
                guard !reduceMotion else {
                    opacity = 1
                    verticalOffset = 0
                    return
                }
                opacity = 0
                verticalOffset = initialOffset
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(BessieDesign.motionStrongEaseOut) {
                    opacity = 1
                    verticalOffset = 0
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    opacity = 1
                    verticalOffset = 0
                }
            }
    }
}

@MainActor
private func announceProjectLaunch(_ message: String) {
    NSAccessibility.post(
        element: NSApplication.shared,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ]
    )
}

private struct ProjectLaunchFailureView: View {
    @ObservedObject var model: ProjectsViewModel
    let presentation: ProjectLaunchFailurePresentation

    var body: some View {
        let partial = presentation.failure.partialResult
        VStack(alignment: .leading, spacing: 14) {
            Text(partial.workspaceID == nil ? "Project did not open" : "Project opened partially")
                .font(.system(size: 18, weight: .semibold))
            Text(presentation.actionableMessage)
                .font(.system(size: 11.5))
                .foregroundStyle(BessieDesign.subtle)
            failureFact("Stopped at", projectStageName(presentation.failure.stage))
            failureFact("Technical detail", String(describing: presentation.failure.ownerError))
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
