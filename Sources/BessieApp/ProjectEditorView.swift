import AppKit
import BessieCore
import SwiftUI

struct ProjectEditorView: View {
    @ObservedObject var model: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss
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
            BessieTopBar(title: draft?.revision == nil ? "Create Project" : "Edit Project") {
                Button("Cancel") { model.discardDraft(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Save") {
                    if model.saveDraft() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BessiePrimaryButtonStyle())
                .disabled(!validationMessages.isEmpty)
            }

            HSplitView {
                projectForm
                    .frame(minWidth: 285, idealWidth: 320, maxWidth: 380)
                layoutEditor
                    .frame(minWidth: 480)
            }

            if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Set(validationMessages)).sorted(), id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle")
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
        .frame(minWidth: 940, idealWidth: 1040, minHeight: 650, idealHeight: 720)
        .background(BessieDesign.background)
        .background(BessieWindowSnapshotProbe(role: "sheet"))
        .onAppear { selectInitialItems() }
        .onChange(of: model.draft?.tabs.map(\.id)) { _, _ in selectInitialItems() }
        .alert("Project could not be saved", isPresented: errorPresented) {
            Button("OK") { model.clearMessage() }
        } message: { Text(model.errorMessage ?? "Unknown error") }
    }

    private var projectForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BessieSectionLabel("PROJECT")
                BessieLabeledInput(label: "Name") {
                    TextField("Project name", text: draftBinding(\.name, default: ""))
                        .bessieInput()
                }
                BessieLabeledInput(label: "Description") {
                    TextField("What this project is for", text: draftBinding(\.projectDescription, default: ""), axis: .vertical)
                        .lineLimit(2...4)
                        .bessieInput()
                }
                BessieLabeledInput(label: "Group", hint: "Optional") {
                    TextField("Team or category", text: groupBinding)
                        .bessieInput()
                }
                BessieLabeledInput(label: "Folder") {
                    HStack(spacing: 6) {
                        TextField("/absolute/path", text: draftBinding(\.workingDirectory, default: ""))
                            .bessieInput()
                        Button("Choose…", action: chooseFolder)
                            .buttonStyle(BessieSecondaryButtonStyle())
                            .accessibilityHint("Choose an absolute working directory")
                    }
                }

                BessieSectionLabel("TABS")
                    .padding(.top, 4)
                VStack(spacing: 5) {
                    ForEach(draft?.tabs ?? []) { tab in
                        HStack(spacing: 5) {
                            Button {
                                selectedTabID = tab.id
                                selectedPaneID = tab.panes.first?.id
                            } label: {
                                HStack {
                                    Image(systemName: "rectangle.stack")
                                    Text(tab.name).lineLimit(1)
                                    Spacer()
                                    Text("\(tab.panes.count)")
                                        .font(.system(size: 9.5, design: .monospaced))
                                        .foregroundStyle(BessieDesign.subtle)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 29)
                                .background(selectedTab?.id == tab.id ? BessieDesign.selected : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button("Move up") { model.moveTab(tab.id, by: -1) }
                                Button("Move down") { model.moveTab(tab.id, by: 1) }
                                Button("Duplicate") { model.duplicateTab(tab.id) }
                                Divider()
                                Button("Remove", role: .destructive) { model.removeTab(tab.id) }
                                    .disabled((draft?.tabs.count ?? 0) <= 1)
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 24, height: 24)
                            }
                            .menuStyle(.borderlessButton)
                            .accessibilityLabel("Actions for tab \(tab.name)")
                        }
                    }
                }
                Button("Add tab") { model.addTab() }
                    .buttonStyle(BessieSecondaryButtonStyle())
            }
            .padding(18)
        }
        .background(BessieDesign.rail)
    }

    private var layoutEditor: some View {
        VStack(spacing: 0) {
            if let tab = selectedTab {
                HStack(spacing: 8) {
                    TextField("Tab name", text: tabNameBinding(tab.id))
                        .bessieInput()
                        .frame(maxWidth: 260)
                    Spacer()
                    Button("Split right") { splitSelected(.right) }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    Button("Split down") { splitSelected(.down) }
                        .buttonStyle(BessieSecondaryButtonStyle())
                }
                .padding(12)
                .background(BessieDesign.panel)

                HSplitView {
                    VStack(spacing: 0) {
                        ProjectLayoutPreview(tab: tab, selectedPaneID: selectedPane?.id)
                            .padding(12)
                        Divider().overlay(BessieDesign.border)
                        commandPreview(tab)
                            .frame(minHeight: 120, maxHeight: 180)
                    }

                    paneInspector(tab)
                        .frame(minWidth: 245, idealWidth: 275, maxWidth: 330)
                }
            } else {
                Text("Add a tab to begin.")
                    .foregroundStyle(BessieDesign.subtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(BessieDesign.background)
    }

    private func paneInspector(_ tab: BessieProjectTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BessieSectionLabel("PANES")
                ForEach(tab.panes) { pane in
                    Button {
                        selectedPaneID = pane.id
                    } label: {
                        HStack {
                            Image(systemName: pane.id == selectedPane?.id ? "rectangle.inset.filled" : "rectangle")
                            Text(pane.label ?? "Shell").lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(pane.id == selectedPane?.id ? BessieDesign.selected : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if let pane = selectedPane {
                    Divider().overlay(BessieDesign.border)
                    BessieLabeledInput(label: "Pane label", hint: "Optional") {
                        TextField("Shell", text: paneLabelBinding(tabID: tab.id, pane: pane))
                            .bessieInput()
                    }
                    BessieLabeledInput(label: "Startup command", hint: "Reviewed text only. One exact line; no secrets or environment fields.") {
                        TextField("Optional command", text: paneCommandBinding(tabID: tab.id, pane: pane))
                            .bessieInput()
                    }
                    if case .split(_, let direction, let ratio) = pane.placement {
                        BessieLabeledInput(label: "Split ratio", hint: "\(direction == .right ? "Left" : "Top") pane: \(Int(ratio * 100))%") {
                            Slider(value: paneRatioBinding(tabID: tab.id, pane: pane), in: 0.1...0.9, step: 0.05)
                        }
                    }
                    Button("Remove pane", role: .destructive) {
                        model.removePane(tabID: tab.id, paneID: pane.id)
                        selectedPaneID = model.draft?.tabs.first(where: { $0.id == tab.id })?.panes.first?.id
                    }
                    .buttonStyle(BessieSecondaryButtonStyle())
                    .disabled(!model.canRemovePane(tabID: tab.id, paneID: pane.id))
                    .help("Only leaf panes can be removed; remove their child splits first.")
                }
            }
            .padding(14)
        }
        .background(BessieDesign.rail)
    }

    private func commandPreview(_ tab: BessieProjectTab) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BessieSectionLabel("EXACT COMMAND PREVIEW")
                ForEach(tab.panes) { pane in
                    HStack(alignment: .top, spacing: 10) {
                        Text(pane.label ?? "Shell")
                            .frame(width: 100, alignment: .leading)
                            .foregroundStyle(BessieDesign.subtle)
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

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Project Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.draft?.workingDirectory = url.standardizedFileURL.path
        }
    }

    private func draftBinding(_ keyPath: WritableKeyPath<BessieProjectDraft, String>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { model.draft?[keyPath: keyPath] ?? defaultValue },
            set: { model.draft?[keyPath: keyPath] = $0 }
        )
    }

    private var groupBinding: Binding<String> {
        Binding(get: { model.draft?.group ?? "" }, set: { model.draft?.group = $0.isEmpty ? nil : $0 })
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
