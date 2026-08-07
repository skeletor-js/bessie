import AppKit
import BessieCore
import SwiftUI

struct ProjectEditorView: View {
    @ObservedObject var model: ProjectsViewModel
    @State private var selectedTabID: UUID?
    @State private var selectedPaneID: UUID?

    private var draft: BessieProjectDraft? { model.draft }
    private var selectedTab: BessieProjectTab? {
        draft?.tabs.first { $0.id == selectedTabID } ?? draft?.tabs.first
    }
    private var selectedPane: BessieProjectPane? {
        selectedTab?.panes.first { $0.id == selectedPaneID } ?? selectedTab?.panes.first
    }

    var body: some View {
        let validationMessages = model.validationMessages
        VStack(spacing: 0) {
            BessieTopBar(title: draft?.revision == nil ? "Create project" : "Edit project") {
                Button("Cancel") { model.discardDraft() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Save project") { _ = model.saveDraft() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BessiePrimaryButtonStyle())
                .disabled(!validationMessages.isEmpty)
            }

            HStack(spacing: 0) {
                ScrollView {
                    projectForm
                }
                    .frame(width: 286)
                layoutEditor
                    .frame(maxWidth: .infinity)
            }

            if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Set(validationMessages)).sorted(), id: \.self) { message in
                        Text(message)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(BessieDesign.strong)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BessieDesign.inset)
                .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
                .accessibilityLabel("Project validation errors")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BessieDesign.background)
        .background(BessieWindowSnapshotProbe())
        .onAppear { selectInitialItems() }
        .onChange(of: model.draft?.tabs.map(\.id)) { _, _ in selectInitialItems() }
        .alert("Project could not be saved", isPresented: errorPresented) {
            Button("OK") { model.clearMessage() }
        } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    private var projectForm: some View {
        VStack(alignment: .leading, spacing: 12) {
                BessieLabeledInput(label: "Project name") {
                    TextField("Project name", text: draftBinding(\.name, default: ""))
                        .bessieInput()
                }
                BessieLabeledInput(
                    label: "Workspace",
                    hint: model.draftTargetConnection?.kind == .ssh ? "absolute path on the target host" : nil
                ) {
                    if model.draftTargetConnection?.kind == .ssh {
                        TextField("/absolute/path/on/target", text: primaryFolderPathBinding)
                            .font(.system(size: 11.5, design: .monospaced))
                            .bessieInput()
                    } else {
                        Button(action: chooseFolders) {
                            Text(draft?.project.primaryFolder?.path ?? "Choose workspace…")
                                .font(.system(size: 11.5, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    }
                }
                BessieLabeledInput(label: "Target herd", hint: "folder paths belong to this host") {
                    Picker("Target herd", selection: targetConnectionBinding) {
                        if let targetConnectionID = draft?.targetConnectionID,
                           !model.connectionDefinitions.contains(where: { $0.id == targetConnectionID }) {
                            Text("\(targetConnectionID) (Missing)").tag(targetConnectionID)
                        }
                        ForEach(model.projectTargetConnections) { connection in
                            Text(connection.enabled ? connection.name : "\(connection.name) (Disabled)")
                                .tag(connection.id)
                        }
                    }
                    .labelsHidden()
                }
                if let targetUnavailableReason = model.draftTargetUnavailableReason {
                    Text(targetUnavailableReason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(BessieDesign.strong)
                        .accessibilityLabel("Target herd unavailable, \(targetUnavailableReason)")
                }
                Divider().overlay(BessieDesign.border)

                BessieSectionLabel("Tabs")
                VStack(spacing: 5) {
                    ForEach(draft?.tabs ?? []) { tab in
                        HStack(spacing: 5) {
                            Button {
                                selectedTabID = tab.id
                                selectedPaneID = tab.panes.first?.id
                            } label: {
                                HStack {
                                    BessieIconView(icon: .browser, size: 14)
                                    Text(tab.name).lineLimit(1)
                                    Spacer()
                                    Text("\(tab.panes.count)")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(BessieDesign.subtle)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 29)
                                .background(selectedTab?.id == tab.id ? BessieDesign.selected : BessieSemanticColor.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            BessieActionPopover(label: "Actions for tab \(tab.name)") { dismiss in
                                BessiePopoverActionRow(title: "Move up", symbol: "arrow.up") {
                                    dismiss(); model.moveTab(tab.id, by: -1)
                                }
                                BessiePopoverActionRow(title: "Move down", symbol: "arrow.down") {
                                    dismiss(); model.moveTab(tab.id, by: 1)
                                }
                                BessiePopoverActionRow(title: "Duplicate", symbol: "plus.square.on.square") {
                                    dismiss(); model.duplicateTab(tab.id)
                                }
                                Divider()
                                BessiePopoverActionRow(
                                    title: "Remove",
                                    symbol: "trash",
                                    destructive: true,
                                    disabled: (draft?.tabs.count ?? 0) <= 1
                                ) {
                                    dismiss(); model.removeTab(tab.id)
                                }
                            }
                        }
                    }
                }
                Button { model.addTab() } label: {
                    HStack(spacing: 6) { BessieIconView(icon: .plus, size: 12); Text("Add tab") }
                }
                    .buttonStyle(BessieSecondaryButtonStyle())
        }
        .padding(16)
        .background(BessieDesign.rail)
    }

    private var layoutEditor: some View {
        VStack(spacing: 0) {
            if let tab = selectedTab {
                HStack(spacing: 8) {
                    Text(tab.name).font(.system(size: 12.5, weight: .medium))
                    Text("drag a divider to change the split")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(BessieDesign.faint)
                    Spacer()
                    Button { splitSelected(.right) } label: {
                        HStack(spacing: 6) { BessieIconView(icon: .squareSplitHorizontal, size: 13); Text("Split right") }
                    }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    Button { splitSelected(.down) } label: {
                        HStack(spacing: 6) { BessieIconView(icon: .squareSplitVertical, size: 13); Text("Split down") }
                    }
                        .buttonStyle(BessieSecondaryButtonStyle())
                }
                .padding(.bottom, 12)

                HStack(spacing: 0) {
                    VStack(spacing: 12) {
                        ProjectLayoutPreview(
                            project: draft?.project,
                            tab: tab,
                            selectedPaneID: selectedPane?.id,
                            onSelectPane: { selectedPaneID = $0 },
                            onChangeRatio: { paneID, ratio in
                                model.updatePaneRatio(tabID: tab.id, paneID: paneID, ratio: ratio)
                            },
                            onAddPane: { splitSelected(.right) }
                        )
                        commandPreview(tab)
                            .frame(height: 135)
                    }

                    paneInspector(tab)
                        .frame(width: 270)
                        .padding(.leading, 16)
                }
            } else {
                Text("Add a tab to begin.")
                    .foregroundStyle(BessieDesign.subtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .background(BessieDesign.background)
    }

    private func paneInspector(_ tab: BessieProjectTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let pane = selectedPane {
                    BessieSectionLabel("Pane \((tab.panes.firstIndex(where: { $0.id == pane.id }) ?? 0) + 1)")
                    BessieLabeledInput(label: "Name", hint: "what the sidebar shows if the agent sets no session title") {
                        TextField("Shell", text: paneLabelBinding(tabID: tab.id, pane: pane))
                            .bessieInput()
                    }
                    BessieLabeledInput(label: "Runs", hint: "one exact line · no secrets") {
                        TextField("Optional command", text: paneCommandBinding(tabID: tab.id, pane: pane))
                            .bessieInput()
                    }
                    BessieLabeledInput(label: "Initial folder") {
                        Picker("Initial folder", selection: paneFolderBinding(tabID: tab.id, pane: pane)) {
                            Text("Use project primary — \(draft?.project.primaryFolder?.name ?? "Folder")")
                                .tag(UUID?.none)
                            ForEach(draft?.folders ?? []) { folder in
                                Text(folder.isPrimary ? "\(folder.name) (currently primary)" : folder.name)
                                    .tag(Optional(folder.id))
                            }
                        }
                        .labelsHidden()
                    }
                    if case .split(_, let direction, let ratio) = pane.placement {
                        BessieLabeledInput(label: "Split ratio", hint: "\(direction == .right ? "Left" : "Top") pane: \(Int(ratio * 100))%") {
                            Slider(value: paneRatioBinding(tabID: tab.id, pane: pane), in: 0.1...0.9, step: 0.05)
                        }
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        model.removePane(tabID: tab.id, paneID: pane.id)
                        selectedPaneID = model.draft?.tabs.first(where: { $0.id == tab.id })?.panes.first?.id
                    } label: { HStack(spacing: 6) { BessieIconView(icon: .x, size: 12); Text("Remove pane") } }
                    .buttonStyle(BessieSecondaryButtonStyle())
                    .disabled(!model.canRemovePane(tabID: tab.id, paneID: pane.id))
                    .help("Only leaf panes can be removed; remove their child splits first.")
                }
            }
            .padding(.leading, 16)
        }
        .background(BessieDesign.rail)
    }

    private func commandPreview(_ tab: BessieProjectTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BessieSectionLabel("What Bessie will run")
                Text("cd \(draft?.project.workingDirectory ?? "Unavailable")")
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(BessieDesign.faint)
                ForEach(Array(tab.panes.enumerated()), id: \.element.id) { index, pane in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)").foregroundStyle(BessieDesign.subtle)
                            Text(pane.label ?? "Shell").frame(width: 70, alignment: .leading)
                            Text(pane.commandDisplay(fallback: "Shell only"))
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                        }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BessieDesign.inset)
    }

    private func splitSelected(_ direction: SplitDirection) {
        guard let tabID = selectedTab?.id, let paneID = selectedPane?.id else { return }
        model.addPane(tabID: tabID, from: paneID, direction: direction)
        selectedPaneID = model.draft?.tabs.first(where: { $0.id == tabID })?.panes.last?.id
    }

    private func selectInitialItems() {
        guard let tabs = model.draft?.tabs, !tabs.isEmpty else {
            selectedTabID = nil; selectedPaneID = nil; return
        }
        if !tabs.contains(where: { $0.id == selectedTabID }) { selectedTabID = tabs.first?.id }
        guard let tab = tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first else { return }
        if !tab.panes.contains(where: { $0.id == selectedPaneID }) { selectedPaneID = tab.panes.first?.id }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Add Project Folders"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            model.addFolders(panel.urls)
        }
    }

    private func draftBinding(_ keyPath: WritableKeyPath<BessieProjectDraft, String>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { model.draft?[keyPath: keyPath] ?? defaultValue },
            set: { model.draft?[keyPath: keyPath] = $0 }
        )
    }

    private func folderNameBinding(_ folderID: UUID) -> Binding<String> {
        Binding(
            get: { model.draft?.folders.first(where: { $0.id == folderID })?.name ?? "" },
            set: { model.renameFolder(folderID, name: $0) }
        )
    }

    private func folderPathBinding(_ folderID: UUID) -> Binding<String> {
        Binding(
            get: { model.draft?.folders.first(where: { $0.id == folderID })?.path ?? "" },
            set: { model.updateFolderPath(folderID, path: $0) }
        )
    }

    private var primaryFolderPathBinding: Binding<String> {
        Binding(
            get: { model.draft?.project.primaryFolder?.path ?? "" },
            set: { path in
                guard let folderID = model.draft?.project.primaryFolder?.id else { return }
                model.updateFolderPath(folderID, path: path)
            }
        )
    }

    private var targetConnectionBinding: Binding<String> {
        Binding(
            get: { model.draft?.targetConnectionID ?? model.defaultProjectConnectionID },
            set: { model.updateTargetConnection($0) }
        )
    }

    private func tabNameBinding(_ tabID: UUID) -> Binding<String> {
        Binding(
            get: { model.draft?.tabs.first(where: { $0.id == tabID })?.name ?? "" },
            set: { model.renameTab(tabID, name: $0) }
        )
    }

    private func paneLabelBinding(tabID: UUID, pane: BessieProjectPane) -> Binding<String> {
        Binding(
            get: { currentPane(tabID: tabID, paneID: pane.id)?.label ?? "" },
            set: { model.updatePaneLabel(tabID: tabID, paneID: pane.id, label: $0) }
        )
    }

    private func paneCommandBinding(tabID: UUID, pane: BessieProjectPane) -> Binding<String> {
        Binding(
            get: { currentPane(tabID: tabID, paneID: pane.id)?.command ?? "" },
            set: { model.updatePaneCommand(tabID: tabID, paneID: pane.id, command: $0) }
        )
    }

    private func paneFolderBinding(tabID: UUID, pane: BessieProjectPane) -> Binding<UUID?> {
        Binding(
            get: { currentPane(tabID: tabID, paneID: pane.id)?.folderID },
            set: { model.updatePaneFolder(tabID: tabID, paneID: pane.id, folderID: $0) }
        )
    }

    private func paneRatioBinding(tabID: UUID, pane: BessieProjectPane) -> Binding<Double> {
        Binding(
            get: {
                guard case .split(_, _, let ratio) = currentPane(tabID: tabID, paneID: pane.id)?.placement else { return 0.5 }
                return ratio
            },
            set: { model.updatePaneRatio(tabID: tabID, paneID: pane.id, ratio: $0) }
        )
    }

    private func currentPane(tabID: UUID, paneID: UUID) -> BessieProjectPane? {
        model.draft?.tabs.first(where: { $0.id == tabID })?.panes.first(where: { $0.id == paneID })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearMessage() } })
    }
}

extension BessieProjectPane {
    func commandDisplay(fallback: String) -> String {
        guard let command, !command.isEmpty else { return fallback }
        return command
    }
}
