import BessieCore
import SwiftUI

enum WorkspaceHierarchySection: String, Hashable {
    case herd
    case workspace
    case tab

    var allTitle: String {
        switch self {
        case .herd: "All Herds"
        case .workspace: "All Workspaces"
        case .tab: "All Tabs"
        }
    }

    var allIcon: BessieIcon? { nil }
}

enum WorkspaceProjectCaptureGate {
    static func isSettled(actionInFlight: Bool, navigationInFlight: Bool) -> Bool {
        !actionInFlight && !navigationInFlight
    }
}

struct WorkspaceHierarchyTabRow: Identifiable, Equatable {
    let id: String
    let title: String
    let paneCount: Int
    let isSelected: Bool
}

enum WorkspaceHierarchyActionAvailability {
    static func canMutate(_ mutationsDisabled: Bool) -> Bool {
        !mutationsDisabled
    }
}

struct WorkspaceHierarchyPresentation: Equatable {
    static let inCardChromeHeight: CGFloat = 0

    let connectionLabel: String
    let workspaceID: String?
    let workspaceLabel: String
    let tabID: String?
    let tabLabel: String
    let paneCount: Int
    let tabs: [WorkspaceHierarchyTabRow]
    let globalSection: WorkspaceHierarchySection?

    init(
        connectionLabel: String,
        projection: HerdrSessionProjection,
        selectedWorkspaceID: String?,
        selectedPaneID: String?,
        globalSection: WorkspaceHierarchySection? = nil,
        globalPaneCount: Int = 0
    ) {
        let workspace = projection.workspaces.first { $0.id == selectedWorkspaceID }
            ?? projection.focusedWorkspace
            ?? projection.workspaces.first
        let workspaceTabs = projection.tabs.filter { $0.workspaceID == workspace?.id }
        let selectedTabID = selectedPaneID.flatMap { paneID in
            projection.panes.first { $0.id == paneID && $0.workspaceID == workspace?.id }?.tabID
        }
        let selectedTab = workspaceTabs.first { $0.id == selectedTabID }
            ?? workspaceTabs.first(where: \.focused)
            ?? workspaceTabs.first

        self.globalSection = globalSection
        self.connectionLabel = globalSection == .herd
            ? WorkspaceHierarchySection.herd.allTitle
            : connectionLabel
        workspaceID = workspace?.id
        workspaceLabel = globalSection == .herd || globalSection == .workspace
            ? WorkspaceHierarchySection.workspace.allTitle
            : (workspace?.label ?? "Workspace")
        tabID = selectedTab?.id
        tabLabel = globalSection == nil
            ? (selectedTab?.label ?? "Tab")
            : WorkspaceHierarchySection.tab.allTitle
        paneCount = globalSection == nil
            ? (selectedTab.map { tab in projection.panes.filter { $0.tabID == tab.id }.count } ?? 0)
            : globalPaneCount
        tabs = workspaceTabs.map { tab in
            WorkspaceHierarchyTabRow(
                id: tab.id,
                title: tab.label,
                paneCount: projection.panes.filter { $0.tabID == tab.id }.count,
                isSelected: tab.id == selectedTab?.id
            )
        }
    }
}

struct WorkspaceHierarchyRail: View {
    let presentation: WorkspaceHierarchyPresentation
    let herds: [HerdPickerRow]
    let workspaces: [WorkspacePickerRow]
    let collapsed: Bool
    let mutationsDisabled: Bool
    let expandRail: () -> Void
    let showAllHerds: () -> Void
    let showAllWorkspaces: () -> Void
    let showAllTabs: () -> Void
    let selectHerd: (HerdPickerRow) -> Void
    let retryHerd: (String) -> Void
    let addHerd: () -> Void
    let manageHerds: () -> Void
    let openWorkspace: (TopologyWorkspaceID) -> Void
    let renameWorkspace: (WorkspacePickerRow) -> Void
    let closeWorkspace: (WorkspacePickerRow) -> Void
    let createWorkspace: () -> Void
    let focusTab: (String) -> Void
    let createTab: () -> Void
    let renameTab: (String, String) -> Void
    let closeTab: (String) -> Void

    @State private var openSection: WorkspaceHierarchySection? = .tab
    @State private var hoveredRowID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if collapsed {
            compactHierarchy
        } else {
            VStack(spacing: 1) {
                selectorRow(
                    section: .herd,
                    icon: .desktop,
                    label: presentation.connectionLabel,
                    addLabel: "Add a herd",
                    addDisabled: false,
                    add: addHerd
                )
                .contextMenu {
                    Button("Add a herd", action: addHerd)
                    Button("Manage herds…", action: manageHerds)
                }
                if openSection == .herd { herdOptions.transition(optionTransition) }

                selectorRow(
                    section: .workspace,
                    icon: .squaresFour,
                    label: presentation.workspaceLabel,
                    addLabel: "New workspace",
                    addDisabled: mutationsDisabled,
                    add: createWorkspace
                )
                .contextMenu {
                    Button("New workspace", action: createWorkspace)
                        .disabled(mutationsDisabled)
                    if presentation.globalSection == nil { currentWorkspaceContextMenu }
                }
                if openSection == .workspace { workspaceOptions.transition(optionTransition) }

                selectorRow(
                    section: .tab,
                    icon: .stack,
                    label: presentation.tabLabel,
                    count: presentation.paneCount,
                    selected: true,
                    addLabel: "New tab",
                    addDisabled: mutationsDisabled || presentation.workspaceID == nil,
                    add: createTab
                )
                .contextMenu {
                    Button("New tab", action: createTab)
                        .disabled(mutationsDisabled || presentation.workspaceID == nil)
                    if presentation.globalSection == nil, let selected = selectedTab {
                        Divider()
                        tabContextMenu(row: selected)
                    }
                }
                if openSection == .tab { tabOptions.transition(optionTransition) }

                Rectangle()
                    .fill(BessieDesign.border)
                    .frame(height: 1)
                    .padding(.top, 9)
                    .padding(.horizontal, 1)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: openSection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Current herd, workspace, and tab")
        }
    }

    private var compactHierarchy: some View {
        VStack(spacing: 2) {
            compactSelector(.herd, icon: .desktop, label: "Herd, \(presentation.connectionLabel)")
                .contextMenu {
                    Button("Add a herd", action: addHerd)
                    Button("Manage herds…", action: manageHerds)
                }
            compactSelector(.workspace, icon: .squaresFour, label: "Workspace, \(presentation.workspaceLabel)")
                .contextMenu {
                    Button("New workspace", action: createWorkspace)
                        .disabled(mutationsDisabled)
                    if presentation.globalSection == nil { currentWorkspaceContextMenu }
                }
            compactSelector(.tab, icon: .stack, label: "Tab, \(presentation.tabLabel)")
                .contextMenu {
                    Button("New tab", action: createTab)
                        .disabled(mutationsDisabled || presentation.workspaceID == nil)
                    if presentation.globalSection == nil, let selected = selectedTab {
                        Divider()
                        tabContextMenu(row: selected)
                    }
                }
            Rectangle().fill(BessieDesign.border).frame(width: 24, height: 1).padding(.vertical, 5)
        }
        .frame(maxWidth: .infinity)
    }

    private func compactSelector(_ section: WorkspaceHierarchySection, icon: BessieIcon, label: String) -> some View {
        Button {
            openSection = section
            expandRail()
        } label: {
            BessieIconView(icon: icon, size: 15)
                .foregroundStyle(section == .tab ? BessieDesign.accent : BessieDesign.subtle)
                .frame(width: 40, height: 28)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint("Expands the sidebar and opens this list")
    }

    private func selectorRow(
        section: WorkspaceHierarchySection,
        icon: BessieIcon,
        label: String,
        count: Int? = nil,
        selected: Bool = false,
        addLabel: String,
        addDisabled: Bool,
        add: @escaping () -> Void
    ) -> some View {
        let rowID = "selector-\(section.rawValue)"
        return HStack(spacing: 0) {
            Button { toggle(section) } label: {
                HStack(spacing: 7) {
                    BessieIconView(icon: icon, size: 14)
                        .foregroundStyle(selected ? BessieDesign.accent : BessieDesign.subtle)
                        .frame(width: 16)
                    Text(label)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if let count {
                        Text("\(count)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(BessieDesign.faint)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: add) {
                BessieIconView(icon: .plus, size: 12).frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(addDisabled)
            .help(addLabel)
            .accessibilityLabel(addLabel)

            Button { toggle(section) } label: {
                BessieIconView(icon: openSection == section ? .caretUp : .caretDown, size: 11)
                    .foregroundStyle(BessieDesign.faint)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.leading, 1)
        .padding(.trailing, 1)
        .background(hoveredRowID == rowID ? BessieDesign.hover : BessieSemanticColor.clear)
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
        .onHover { hoveredRowID = $0 ? rowID : nil }
        .accessibilityElement(children: .contain)
        .accessibilityValue(openSection == section ? "Expanded" : "Collapsed")
    }

    private var herdOptions: some View {
        VStack(spacing: 1) {
            optionButton(
                id: "all-herds",
                title: WorkspaceHierarchySection.herd.allTitle,
                icon: WorkspaceHierarchySection.herd.allIcon,
                selected: presentation.globalSection == .herd,
                action: showAllHerds
            )
            let alternatives = presentation.globalSection == nil
                ? herds.filter { !$0.isSelected }
                : herds
            if alternatives.isEmpty {
                emptyRow("No other herds")
            } else {
                ForEach(alternatives) { row in
                    optionButton(
                        id: "herd-\(row.id)",
                        title: row.title,
                        icon: row.kind == .local ? .desktop : .hardDrives
                    ) {
                        if row.isFresh { selectHerd(row) }
                        else if row.canRetry { retryHerd(row.id) }
                        else { manageHerds() }
                    }
                    .accessibilityLabel("\(row.title), \(row.detail)")
                    .accessibilityHint(row.isFresh ? "Switch to this herd" : (row.canRetry ? "Retry this herd" : "Open herd settings"))
                    .contextMenu { herdContextMenu(row) }
                }
            }
            optionButton(id: "manage-herds", title: "Manage herds…", icon: .gear, action: manageHerds)
        }
    }

    private var workspaceOptions: some View {
        VStack(spacing: 1) {
            optionButton(
                id: "all-workspaces",
                title: WorkspaceHierarchySection.workspace.allTitle,
                icon: WorkspaceHierarchySection.workspace.allIcon,
                selected: presentation.globalSection == .workspace,
                action: showAllWorkspaces
            )
            let currentConnectionID = currentWorkspaceRow?.id.connectionID
            let options = workspaces
                .filter { $0.id.connectionID == currentConnectionID }
                .sorted {
                    let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                    return order == .orderedSame
                        ? $0.id.workspaceID < $1.id.workspaceID
                        : order == .orderedAscending
                }
            if options.isEmpty { emptyRow("No workspaces") }
            ForEach(options) { row in
                optionButton(id: "workspace-\(row.id.connectionID)-\(row.id.workspaceID)", title: row.title) {
                    openWorkspace(row.id)
                }
                .accessibilityLabel("\(row.title), \(row.detail)")
                .contextMenu {
                    Button("Open workspace") { openWorkspace(row.id) }
                    Button("Rename") { renameWorkspace(row) }
                        .disabled(!WorkspaceHierarchyActionAvailability.canMutate(mutationsDisabled))
                    Divider()
                    Button("Close workspace", role: .destructive) { closeWorkspace(row) }
                        .disabled(!WorkspaceHierarchyActionAvailability.canMutate(mutationsDisabled))
                }
            }
        }
    }

    private var tabOptions: some View {
        VStack(spacing: 1) {
            optionButton(
                id: "all-tabs",
                title: WorkspaceHierarchySection.tab.allTitle,
                icon: WorkspaceHierarchySection.tab.allIcon,
                selected: presentation.globalSection == .tab,
                action: showAllTabs
            )
            if presentation.tabs.isEmpty { emptyRow("No tabs") }
            ForEach(presentation.tabs.sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }) { row in
                optionButton(id: "tab-\(row.id)", title: row.title, count: row.paneCount) {
                    focusTab(row.id)
                }
                .accessibilityLabel("\(row.title), \(row.paneCount) panes")
                .contextMenu { tabContextMenu(row: row) }
            }
        }
    }

    private var currentWorkspaceRow: WorkspacePickerRow? {
        guard let workspaceID = presentation.workspaceID else { return nil }
        return workspaces.first { $0.id.workspaceID == workspaceID && $0.isSelected }
            ?? workspaces.first { $0.id.workspaceID == workspaceID }
    }

    private var selectedTab: WorkspaceHierarchyTabRow? {
        presentation.tabs.first(where: \.isSelected)
    }

    @ViewBuilder private var currentWorkspaceContextMenu: some View {
        if let row = currentWorkspaceRow {
            Divider()
            Button("Open workspace") { openWorkspace(row.id) }
            Button("Rename") { renameWorkspace(row) }
                .disabled(!WorkspaceHierarchyActionAvailability.canMutate(mutationsDisabled))
            Divider()
            Button("Close workspace", role: .destructive) { closeWorkspace(row) }
                .disabled(!WorkspaceHierarchyActionAvailability.canMutate(mutationsDisabled))
        }
    }

    @ViewBuilder private func herdContextMenu(_ row: HerdPickerRow) -> some View {
        if row.isFresh {
            Button("Switch to herd") { selectHerd(row) }
        } else if row.canRetry {
            Button("Retry herd") { retryHerd(row.id) }
        }
        Button("Manage herds…", action: manageHerds)
    }

    @ViewBuilder private func tabContextMenu(row: WorkspaceHierarchyTabRow) -> some View {
        Button("Rename") { renameTab(row.id, row.title) }
            .disabled(!WorkspaceHierarchyActionAvailability.canMutate(mutationsDisabled))
        Divider()
        Button("Close tab", role: .destructive) { closeTab(row.id) }
            .disabled(!WorkspaceHierarchyActionAvailability.canMutate(mutationsDisabled))
    }

    private func optionButton(
        id: String,
        title: String,
        icon: BessieIcon? = nil,
        count: Int? = nil,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            openSection = nil
            action()
        } label: {
            HStack(spacing: 7) {
                if let icon { BessieIconView(icon: icon, size: 13).frame(width: 15) }
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(BessieDesign.faint)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.text)
            .padding(.leading, 30)
            .padding(.trailing, 7)
            .frame(maxWidth: .infinity, minHeight: 29, alignment: .leading)
            .contentShape(Rectangle())
            .background(hoveredRowID == id ? BessieDesign.hover : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .onHover { hoveredRowID = $0 ? id : nil }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func emptyRow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5))
            .foregroundStyle(BessieDesign.faint)
            .padding(.leading, 30)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var optionTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    private func toggle(_ section: WorkspaceHierarchySection) {
        openSection = openSection == section ? nil : section
    }
}
