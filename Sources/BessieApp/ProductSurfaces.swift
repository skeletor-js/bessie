import AppKit
import BessieCore
import SwiftUI

enum ProductDestination: String, CaseIterable, Identifiable {
    case herd = "The herd"
    case workspaces = "Workspaces"
    case projects = "Projects"
    case workspace = "Workspace"
    case attention = "Attention"
    case agent = "Agent"
    case settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .herd: "circle.grid.3x3"
        case .workspaces: "square.grid.2x2"
        case .projects: "folder.badge.gearshape"
        case .workspace: "rectangle.split.3x1"
        case .attention: "bell"
        case .agent: "terminal"
        case .settings: "gearshape"
        }
    }

    static var initial: ProductDestination {
        guard let raw = ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased() else { return .workspaces }
        if raw == "new-process" { return .workspace }
        if raw == "herd" { return .herd }
        if raw == "agent-detail" { return .agent }
        if raw == "project-capture" || raw == "project-launch-review" { return .projects }
        return ProductDestination.allCases.first { $0.rawValue.lowercased() == raw } ?? .workspaces
    }

    static func navigationTarget(for command: BessieShortcutCommand) -> ProductDestination? {
        command == .projectsPicker ? .projects : nil
    }
}

struct BessieProductShell: View {
    @ObservedObject var model: ConnectionViewModel
    @ObservedObject var fleet: ConnectionFleetViewModel
    let projection: HerdrSessionProjection
    let terminalEndpoint: HerdrTerminalEndpoint
    @ObservedObject var terminalRegistry: TerminalControllerRegistry
    @EnvironmentObject private var settings: BessieSettingsModel
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination: ProductDestination = .initial
    @State private var selectedWorkspaceID: String?
    @State private var selectedPaneID: String?
    @State private var processAutomationStarted = false
    @StateObject private var shortcuts = BessieKeyboardShortcutCoordinator()
    @State private var sidebarCollapsed = false
    @State private var showCommandPalette = false
    @State private var shortcutEditor: ProductEditor?
    @State private var shortcutClose: PendingClose?
    @ObservedObject var projects: ProjectsViewModel

    private var surfaces: BessieSurfaceProjection { BessieSurfaceProjection(projection: projection) }
    private var activeNotificationPaneID: String? {
        guard scenePhase == .active, destination == .workspace || destination == .agent else { return nil }
        let candidate = selectedPaneID ?? projection.focusedPane?.id
        guard let candidate,
              let pane = projection.panes.first(where: { $0.id == candidate }),
              pane.workspaceID == selectedWorkspaceID
        else { return nil }
        return candidate
    }
    private var notificationSignature: String {
        let panes = surfaces.notificationPanes
            .map { "\($0.paneID):\($0.state.rawValue):\($0.revision)" }
            .joined(separator: "|")
        return "\(model.activeConnection.id)|\(settings.preferences.notifications.rawValue)|\(scenePhase)|\(activeNotificationPaneID ?? "-")|\(panes)"
    }
    private var notificationRouteSignature: String {
        let pending = notifications.pendingTarget?.paneID ?? "-"
        let panes = projection.panes
            .map { "\($0.id):\($0.workspaceID):\($0.tabID)" }
            .sorted()
            .joined(separator: "|")
        return "\(pending)|\(panes)"
    }
    private var shortcutContextSignature: String {
        [
            destination.rawValue,
            selectedWorkspaceID ?? "-",
            selectedPaneID ?? "-",
            projection.focusedWorkspace?.id ?? "-",
            projection.focusedTab?.id ?? "-",
            projection.focusedPane?.id ?? "-",
            projection.workspaces.map(\.id).joined(separator: ","),
            projection.tabs.map(\.id).joined(separator: ","),
            projection.panes.map(\.id).joined(separator: ","),
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            BessieCowprintTexture(base: BessieDesign.window, crop: activeCrop, intensityScale: 0.9)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: BessieDesign.cardGap) {
                    if !sidebarCollapsed {
                        productRail
                            .bessieSurface(base: BessieDesign.rail, crop: railCrop)
                    }

                    productContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .bessieSurface(base: BessieDesign.background, crop: activeCrop)
                }
                .padding(.horizontal, BessieDesign.cardGap)
                .padding(.bottom, BessieDesign.cardGap - 2)

                BessieStatusLine(
                    workspaceCount: projection.workspaces.count,
                    attentionCount: surfaces.attention.count,
                    connectionCount: fleet.connectedCount
                )
            }
        }
        .background(BessieDesign.window)
        .foregroundStyle(BessieDesign.text)
        .tint(BessieDesign.strong)
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.48)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showCommandPalette = false }
                    BessieCommandPalette(
                        close: { showCommandPalette = false },
                        perform: { command in handleShortcut(command) }
                    )
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(20)
            }
        }
        .animation(.easeOut(duration: 0.12), value: showCommandPalette)
        .onAppear {
            shortcuts.start { command in handleShortcut(command) }
            if ProcessInfo.processInfo.environment["BESSIE_COMMAND_PALETTE_PREVIEW"] != nil {
                showCommandPalette = true
            }
            if ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"] != nil {
                selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
                selectedPaneID = projection.focusedPane?.id
                if ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased() == "project-capture" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        projects.beginCaptureCurrentWorkspace()
                    }
                }
                if ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased() == "project-launch-review" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        projects.presentDesignPreviewLaunchReview(
                            connectionName: model.activeConnection.name
                        )
                    }
                }
            } else if settings.preferences.startupBehavior == .lastWorkspace,
               let last = settings.lastWorkspaceID(for: model.activeConnection.id),
               projection.workspaces.contains(where: { $0.id == last }) {
                selectedWorkspaceID = last
                destination = .workspace
            } else {
                selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
                destination = .workspaces
            }
            routePendingNotification()
        }
        .onDisappear { shortcuts.stop() }
        .onChange(of: projection.workspaces.count) { _, count in
            if count > 0,
               ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_TRIGGER"] == "live-two-pane" {
                selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
                destination = .workspace
            }
        }
        .onChange(of: projection.panes.count) { _, count in
            guard count >= 2,
                  ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_TRIGGER"] == "live-two-pane"
            else { return }
            selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
            selectedPaneID = projection.focusedPane?.id
            destination = .workspace
            BessieWindowSnapshot.captureWhenReady(registry: terminalRegistry, paneIDs: Set(projection.panes.map(\.id)))
        }
        .onChange(of: selectedWorkspaceID) { _, id in
            settings.recordLastWorkspace(id, connectionID: model.activeConnection.id)
        }
        .task(id: "\(projection.panes.count)-\(model.agentCatalog.items.count)") { runProcessAutomationIfRequested() }
        .task(id: notificationSignature) {
            notifications.reconcile(
                connectionID: model.activeConnection.id,
                panes: surfaces.notificationPanes,
                policy: settings.preferences.notifications,
                activePaneID: activeNotificationPaneID
            )
        }
        .task(id: notificationRouteSignature) { routePendingNotification() }
        .task(id: shortcutContextSignature) {
            shortcuts.update { command in handleShortcut(command) }
        }
        .sheet(item: $shortcutEditor) { editor in
            ProductEditorSheet(editor: editor) { action in
                model.perform(action)
                shortcutEditor = nil
            }
        }
        .confirmationDialog(
            shortcutClose?.title ?? "Close?",
            isPresented: Binding(get: { shortcutClose != nil }, set: { if !$0 { shortcutClose = nil } }),
            titleVisibility: .visible
        ) {
            if let shortcutClose {
                Button(shortcutClose.buttonTitle, role: .destructive) {
                    model.perform(shortcutClose.action)
                    self.shortcutClose = nil
                }
            }
            Button("Cancel", role: .cancel) { shortcutClose = nil }
        } message: { Text(shortcutClose?.message(in: projection) ?? "") }
        .alert("Action failed", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.clearActionError() } }
        )) {
            Button("OK") { model.clearActionError() }
        } message: { Text(model.actionError ?? "No error details were returned.") }
        .projectConnectionSync(
            model: projects,
            connection: model.projectMaterializationConnection,
            snapshot: projection.snapshot
        )
        .projectLaunchPresentation(model: projects, navigate: openProjectHandoff)
    }

    @ViewBuilder private var productContent: some View {
        switch destination {
        case .herd:
            HerdSurface(
                fleet: fleet,
                openPane: openConnectedAgent,
                inspectPane: { connected in
                    _ = fleet.activate(connected)
                    selectedPaneID = connected.paneID
                    selectedWorkspaceID = connected.workspaceID
                    destination = .agent
                }
            )
        case .workspaces:
            WorkspacesSurface(model: model, projection: projection) { workspaceID in
                selectedWorkspaceID = workspaceID
                selectedPaneID = nil
                destination = .workspace
            }
        case .projects:
            ProjectsSurface(model: projects)
        case .workspace:
            WorkspaceSurface(
                model: model,
                projection: projection,
                endpoint: terminalEndpoint,
                registry: terminalRegistry,
                selectedWorkspaceID: $selectedWorkspaceID,
                selectedPaneID: $selectedPaneID,
                paneGap: settings.preferences.paneGap,
                terminalFontSize: settings.preferences.terminalFontSize
            )
        case .attention:
            AttentionSurface(items: surfaces.attention, open: openPane)
        case .agent:
            AgentDetailSurface(
                model: model,
                projection: projection,
                endpoint: terminalEndpoint,
                registry: terminalRegistry,
                selectedPaneID: $selectedPaneID,
                terminalFontSize: settings.preferences.terminalFontSize,
                openWorkspace: {
                    if let pane = selectedAgentPane { selectedWorkspaceID = pane.workspaceID }
                    destination = .workspace
                }
            )
        case .settings:
            BessieSettingsView(embedded: true, runtimeDiagnostic: model.runtimeDiagnostic)
        }
    }

    private var productRail: some View {
        VStack(spacing: 0) {
            HStack {
                BessieProductMark()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 13)
            .padding(.bottom, 8)

            Button { destination = .settings } label: {
                HStack(spacing: 7) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                    Text("ALL CONNECTIONS")
                        .lineLimit(1)
                    Spacer()
                    Text("\(fleet.connectedCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(BessieDesign.text)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(BessieDesign.inset)
                .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    railDestination(.herd)
                    railDestination(.attention)
                    railDestination(.workspaces)
                    railDestination(.projects)

                    railGroupLabel("OPEN")
                        .padding(.top, 17)
                    ForEach(surfaces.workspaces) { item in
                        Button {
                            model.perform(.workspaceFocus(id: item.id)) { _ in
                                selectedWorkspaceID = item.id
                                selectedPaneID = nil
                                destination = .workspace
                            }
                        } label: {
                            railRow(
                                symbol: item.id == selectedWorkspaceID ? "folder.fill" : "folder",
                                label: item.label,
                                end: "\(item.paneCount)",
                                selected: (destination == .workspace || destination == .agent) && item.id == selectedWorkspaceID,
                                monospaced: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.label), \(item.paneCount) pane\(item.paneCount == 1 ? "" : "s")")
                    }

                    if (destination == .workspace || destination == .agent), let workspace = currentWorkspace {
                        railGroupLabel("TABS · \(workspace.tabCount)")
                            .padding(.top, 17)
                        ForEach(currentTabs) { tab in
                            Button {
                                model.perform(.tabFocus(id: tab.id))
                                selectedPaneID = nil
                            } label: {
                                railRow(
                                    symbol: "terminal",
                                    label: tab.label,
                                    end: "\(tab.paneCount)",
                                    selected: tab.focused,
                                    state: AgentSemanticState(herdrValue: tab.agentStatus)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(tab.label), \(tab.paneCount) pane\(tab.paneCount == 1 ? "" : "s")")
                        }

                        railGroupLabel("PANES")
                            .padding(.top, 17)
                        ForEach(currentPanes) { pane in
                            Button {
                                selectedPaneID = pane.id
                                model.perform(.paneFocus(id: pane.id))
                                destination = pane.agent == nil ? .workspace : .agent
                            } label: {
                                railRow(
                                    symbol: nil,
                                    label: pane.label ?? pane.agent ?? pane.title ?? "Untitled pane",
                                    end: nil,
                                    selected: selectedPaneID == pane.id || pane.focused,
                                    state: AgentSemanticState(herdrValue: pane.agentStatus),
                                    monospaced: true
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(pane.label ?? pane.agent ?? pane.title ?? "Untitled pane"), \(AgentSemanticState(herdrValue: pane.agentStatus).title)")
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }

            Divider().overlay(BessieDesign.border)
            Button { destination = .settings } label: {
                railRow(symbol: "gearshape", label: "Settings", end: nil, selected: destination == .settings)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .frame(width: BessieDesign.railWidth)
        .clipped()
    }

    private var selectedAgentPane: PaneProjection? {
        projection.panes.first { $0.id == selectedPaneID } ?? projection.focusedPane ?? projection.panes.first
    }

    private var currentWorkspace: WorkspaceProjection? {
        if destination == .agent, let selectedAgentPane {
            return projection.workspaces.first { $0.id == selectedAgentPane.workspaceID }
        }
        return projection.workspaces.first { $0.id == selectedWorkspaceID } ?? projection.focusedWorkspace
    }

    private var currentTabs: [TabProjection] {
        guard let id = currentWorkspace?.id else { return [] }
        return projection.tabs.filter { $0.workspaceID == id }
    }

    private var currentTab: TabProjection? {
        currentTabs.first(where: \.focused) ?? currentTabs.first
    }

    private var currentPanes: [PaneProjection] {
        guard let id = currentTab?.id else { return [] }
        return projection.panes.filter { $0.tabID == id }
    }

    private var activeCrop: BessieCowCrop {
        switch destination {
        case .herd: .herd
        case .workspaces: .workspaces
        case .projects: .workspaces
        case .workspace: .workspace
        case .attention: .attention
        case .agent: .agent
        case .settings: .settings
        }
    }

    private var railCrop: BessieCowCrop {
        BessieCowCrop(
            ink: max(0.035, activeCrop.ink * 0.82),
            scale: activeCrop.scale,
            position: activeCrop.position
        )
    }

    @ViewBuilder private func railDestination(_ item: ProductDestination, label: String? = nil) -> some View {
        Button { destination = item } label: {
            railRow(
                symbol: item.symbol,
                label: label ?? item.rawValue,
                end: item == .attention && !surfaces.attention.isEmpty ? "\(surfaces.attention.count)" : nil,
                selected: destination == item || (item == .herd && destination == .agent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? item.rawValue)
    }

    private func railGroupLabel(_ text: String) -> some View {
        Text(text)
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.45)
        .foregroundStyle(BessieDesign.faint)
        .padding(.horizontal, 9)
        .frame(height: 22)
    }

    private func railRow(
        symbol: String?,
        label: String,
        end: String?,
        selected: Bool,
        state: AgentSemanticState? = nil,
        monospaced: Bool = false
    ) -> some View {
        HStack(spacing: 9) {
            if selected {
                Rectangle().fill(BessieDesign.accent).frame(width: 2.5, height: 16)
                    .offset(x: -9)
                    .padding(.trailing, -2.5)
            }
            if let state { AgentStateGlyph(state: state, size: 6) }
            else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.subtle)
                    .frame(width: 15)
            }
            Text(label)
                .font(.system(size: 12.5, weight: selected ? .medium : .regular, design: monospaced ? .monospaced : .default))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let end {
                Text(end)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(itemEndColor(label: label))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: BessieDesign.rowHeight)
        .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.text)
        .background(selected ? BessieDesign.selected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func itemEndColor(label: String) -> Color {
        label == ProductDestination.attention.rawValue && !surfaces.attention.isEmpty ? BessieDesign.strong : BessieDesign.faint
    }

    private func openPane(_ paneID: String) {
        guard let target = surfaces.openTarget(paneID: paneID) else { return }
        model.openPane(target) { _ in
            selectedWorkspaceID = target.workspaceID
            selectedPaneID = target.paneID
            destination = .workspace
        }
    }

    private func openConnectedAgent(_ connected: ConnectedAgentProjection) {
        guard let targetModel = fleet.activate(connected) else { return }
        let target = PaneOpenTarget(
            workspaceID: connected.workspaceID,
            tabID: connected.tabID,
            paneID: connected.paneID
        )
        targetModel.openPane(target) { _ in
            selectedWorkspaceID = connected.workspaceID
            selectedPaneID = connected.paneID
            destination = .workspace
        }
    }

    private func openProjectHandoff(_ handoff: ProjectWorkspaceHandoff) {
        model.openProjectHandoff(handoff) { _ in
            selectedWorkspaceID = handoff.workspaceID
            selectedPaneID = handoff.paneID
            destination = .workspace
        }
    }

    private func handleShortcut(_ command: BessieShortcutCommand) {
        if model.actionInFlight {
            switch command {
            case .showCommandPalette, .showSettings, .projectsPicker, .saveCurrentWorkspaceAsProject, .workspacePicker, .openNotificationTarget, .toggleSidebar:
                break
            default:
                return
            }
        }
        let workspace = currentWorkspace ?? projection.focusedWorkspace ?? projection.workspaces.first
        let tabs = workspace.map { item in projection.tabs.filter { $0.workspaceID == item.id } } ?? []
        let tab = tabs.first(where: \.focused) ?? tabs.first
        let paneIDs = tab.flatMap { projection.layouts[$0.id]?.root.paneIDs } ?? []
        let paneID = BessiePaneActionTarget.resolve(
            selectedPaneID: selectedPaneID,
            visiblePaneIDs: Set(paneIDs),
            projection: projection
        )

        switch command {
        case .showCommandPalette:
            showCommandPalette.toggle()
        case .showSettings:
            destination = .settings
        case .projectsPicker:
            destination = ProductDestination.navigationTarget(for: command) ?? destination
        case .saveCurrentWorkspaceAsProject:
            destination = .projects
            projects.beginCaptureCurrentWorkspace()
        case .newWorkspace:
            shortcutEditor = .createWorkspace
        case .renameWorkspace:
            if let workspace { shortcutEditor = .renameWorkspace(id: workspace.id, value: workspace.label) }
        case .closeWorkspace:
            if let workspace { shortcutClose = .workspace(workspace.id) }
        case .workspacePicker:
            destination = .workspaces
        case .openNotificationTarget:
            if let item = surfaces.attention.first { openPane(item.paneID) }
            else { destination = .attention }
        case .newTab:
            if let workspace { model.perform(.tabCreate(workspaceID: workspace.id, cwd: nil, label: nil, focus: true)) }
        case .renameTab:
            if let tab { shortcutEditor = .renameTab(id: tab.id, value: tab.label) }
        case .previousTab:
            focusTab(offset: -1, tabs: tabs, current: tab)
        case .nextTab:
            focusTab(offset: 1, tabs: tabs, current: tab)
        case .switchTab(let index):
            guard tabs.indices.contains(index - 1) else { return }
            selectedPaneID = nil
            model.perform(.tabFocus(id: tabs[index - 1].id))
        case .closeTab:
            if let tab { shortcutClose = .tab(tab.id) }
        case .renamePane:
            if let paneID, let pane = projection.panes.first(where: { $0.id == paneID }) {
                shortcutEditor = .renamePane(id: paneID, value: pane.label ?? "")
            }
        case .focusPane(let direction):
            guard let paneID, let tab, let layout = projection.layouts[tab.id],
                  let target = BessiePaneNavigation.target(from: paneID, direction: direction, in: layout.root)
            else { return }
            selectedPaneID = target
            model.perform(.paneFocus(id: target))
        case .swapPane(let direction):
            if let paneID { model.perform(.paneSwap(id: paneID, direction: direction)) }

        case .splitPane(let direction):
            if let paneID { model.perform(.paneSplit(targetPaneID: paneID, direction: direction, ratio: 0.5, cwd: nil, focus: true)) }
        case .closePane:
            if let paneID { shortcutClose = .pane(paneID) }
        case .zoomPane:
            if let paneID { model.perform(.paneZoom(id: paneID, mode: .toggle)) }
        case .resizePane(let direction):
            if let paneID { model.perform(.paneResize(id: paneID, direction: direction, amount: 0.05)) }
        case .toggleSidebar:
            sidebarCollapsed.toggle()
        }
    }

    private func focusTab(offset: Int, tabs: [TabProjection], current: TabProjection?) {
        guard !tabs.isEmpty else { return }
        let index = current.flatMap { item in tabs.firstIndex { $0.id == item.id } } ?? 0
        let target = tabs[(index + offset + tabs.count) % tabs.count]
        selectedPaneID = nil
        model.perform(.tabFocus(id: target.id))
    }

    private func routePendingNotification() {
        guard let pending = notifications.pendingTarget else { return }
        if let connectionID = notifications.pendingConnectionID,
           connectionID != model.activeConnection.id {
            _ = fleet.activate(connectionID: connectionID)
            return
        }
        guard let target = BessieNotificationRoute.resolve(pending: pending, projection: projection) else {
            destination = .attention
            return
        }
        model.openPane(target) { _ in
            notifications.consumePendingTarget(connectionID: model.activeConnection.id, paneID: pending.paneID)
            selectedWorkspaceID = target.workspaceID
            selectedPaneID = target.paneID
            destination = .workspace
        }
    }

    private func runProcessAutomationIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BESSIE_PROCESS_LIVE_AUTOMATION"] == "1",
              !processAutomationStarted,
              let targetPaneID = projection.focusedPane?.id ?? projection.panes.first?.id
        else { return }
        let agentKind = environment["BESSIE_PROCESS_AGENT_KIND"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let process: NewProcessChoice
        if let agentKind, !agentKind.isEmpty {
            guard let item = model.agentCatalog.items.first(where: { $0.kind == agentKind }), item.availability.isAvailable else { return }
            let existing = Set(projection.panes.compactMap { $0.label ?? $0.agent })
            process = .agent(kind: agentKind, name: AgentSemanticName.unique(kind: agentKind, existing: existing), args: [], timeoutMilliseconds: 30_000)
        } else {
            process = .shell
        }
        processAutomationStarted = true
        model.launch(
            placement: .split(targetPaneID: targetPaneID, direction: .down, cwd: environment["BESSIE_PROCESS_CWD"]),
            process: process
        ) { result in
            selectedPaneID = result.paneID
            BessieDiagnosticLog.append(
                "Process launch pane=\(result.paneID) kind=\(agentKind?.isEmpty == false ? agentKind! : "shell") agent_started=\(result.agentStarted) shell_preserved=\(result.agentError != nil)"
            )
        }
    }
}

private enum HerdFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case blocked = "Needs you"
    case working = "Working"
    case done = "Done"
    case idle = "Idle"
    var id: String { rawValue }

    func includes(_ state: AgentSemanticState) -> Bool {
        self == .all || rawValue.lowercased() == state.rawValue
    }
}

private struct HerdSurface: View {
    @ObservedObject var fleet: ConnectionFleetViewModel
    let openPane: (ConnectedAgentProjection) -> Void
    let inspectPane: (ConnectedAgentProjection) -> Void
    @State private var filter: HerdFilter = .all

    private var agents: [ConnectedAgentProjection] {
        fleet.agents.sorted { stateRank($0.agent) < stateRank($1.agent) }
    }

    private var panes: [ConnectedAgentProjection] {
        agents.filter { filter.includes(AgentSemanticState(herdrValue: $0.agent.agentStatus)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: "The herd") {
                if !agents.isEmpty {
                    Text("\(agents.count) AGENT\(agents.count == 1 ? "" : "S")")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BessieDesign.subtle)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(BessieDesign.inset)
                        .overlay { RoundedRectangle(cornerRadius: BessieDesign.controlRadius).stroke(BessieDesign.border, lineWidth: 1) }

                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !agents.isEmpty {
                        HStack(alignment: .bottom) {
                            Spacer()
                            herdFilters
                        }
                        .padding(.bottom, 18)
                    }

                    if panes.isEmpty {
                        ProductEmptyState(
                            symbol: "circle.grid.3x3",
                            title: agents.isEmpty ? "No agents running" : "No matching agents",
                            detail: agents.isEmpty ? "Start an agent from a workspace." : "Choose another filter.",
                            actionTitle: "",
                            action: nil
                        )
                        .frame(minHeight: 300)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                            ForEach(panes) { pane in
                                herdCard(pane)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 25)
                .padding(.bottom, 50)
            }
        }

    }

    private var herdFilters: some View {
        HStack(spacing: 0) {
            ForEach(HerdFilter.allCases) { item in
                Button(item.rawValue) { filter = item }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: filter == item ? .semibold : .regular))
                    .foregroundStyle(filter == item ? BessieDesign.strong : BessieDesign.subtle)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(filter == item ? BessieDesign.selected : Color.clear)
            }
        }
        .padding(2)
        .background(BessieDesign.inset)
        .overlay { RoundedRectangle(cornerRadius: BessieDesign.controlRadius).stroke(BessieDesign.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }

    private func herdCard(_ connected: ConnectedAgentProjection) -> some View {
        let pane = connected.agent
        let state = AgentSemanticState(herdrValue: pane.agentStatus)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AgentStateGlyph(state: state, size: 7)
                Text(pane.identity)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BessieDesign.strong)
                    .lineLimit(1)
                Spacer()
                Text(state.title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(stateColor(state))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Rectangle().fill(BessieDesign.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                Text(location(for: connected))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                    .lineLimit(1)
                if let activity = activity(for: pane, state: state) {
                    Text(activity)
                        .font(.system(size: 12))
                        .foregroundStyle(BessieDesign.text)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                } else {
                    Spacer().frame(minHeight: 48)
                }
            }
            .padding(12)

            HStack(spacing: 7) {
                Spacer()
                Button("Open pane") { openPane(connected) }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Details") { inspectPane(connected) }
                    .buttonStyle(BessiePrimaryButtonStyle())
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(BessieDesign.inset.opacity(0.7))
        }
        .background(BessieDesign.panel)
        .overlay {
            RoundedRectangle(cornerRadius: BessieDesign.cardRadius)
                .stroke(state == .blocked ? BessieDesign.strong.opacity(0.72) : BessieDesign.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.cardRadius))
    }

    private func stateRank(_ pane: AgentProjection) -> Int {
        switch AgentSemanticState(herdrValue: pane.agentStatus) {
        case .blocked: 0
        case .working: 1
        case .done: 2
        case .idle: 3
        case .unknown: 4
        }
    }

    private func stateColor(_ state: AgentSemanticState) -> Color {
        switch state {
        case .blocked: BessieDesign.strong
        case .working: BessieDesign.running
        case .done: BessieDesign.done
        case .idle, .unknown: BessieDesign.idle
        }
    }

    private func location(for connected: ConnectedAgentProjection) -> String {
        let pane = connected.agent
        let workspace = connected.workspaceLabel ?? "Untitled workspace"
        let tab = connected.tabLabel ?? "Untitled tab"
        return "\(connected.connectionName) / \(workspace) / \(tab) / \(pane.label ?? pane.title ?? "Untitled pane")"
    }

    private func activity(for pane: AgentProjection, state: AgentSemanticState) -> String? {
        if let title = pane.title, !title.isEmpty { return title }
        switch state {
        case .blocked: return "Open the pane to respond."
        case .done: return "Open the pane to review."
        case .working, .idle, .unknown: return nil
        }
    }
}

private struct AgentDetailSurface: View {
    private enum WorkbenchSection: String, CaseIterable {
        case details = "Details"
        case changes = "Changes"
    }

    @ObservedObject var model: ConnectionViewModel
    let projection: HerdrSessionProjection
    let endpoint: HerdrTerminalEndpoint
    @ObservedObject var registry: TerminalControllerRegistry
    @Binding var selectedPaneID: String?
    let terminalFontSize: Double
    let openWorkspace: () -> Void
    @State private var prompt = ""
    @State private var editor: ProductEditor?
    @State private var workbenchSection: WorkbenchSection = .changes
    @StateObject private var followFiles = FollowFilesViewModel()

    private var pane: PaneProjection? {
        projection.panes.first { $0.id == selectedPaneID } ?? projection.focusedPane ?? projection.panes.first
    }
    private var workspace: WorkspaceProjection? { projection.workspaces.first { $0.id == pane?.workspaceID } }
    private var tab: TabProjection? { projection.tabs.first { $0.id == pane?.tabID } }
    private var controller: PaneTerminalController? { pane.flatMap { registry.controllers[$0.id] } }
    private var followContextSignature: String {
        "\(model.activeConnection.id)::\(pane?.id ?? "-")::\(pane?.cwd ?? "-")"
    }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(
                crumbs: [workspace?.label, tab?.label].compactMap { $0 },
                title: pane?.agent ?? pane?.label ?? pane?.title ?? "Pane"
            ) {
                if let pane {
                    Button("Rename") { editor = .renamePane(id: pane.id, value: pane.label ?? "") }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    Button("Open workspace", action: openWorkspace)
                        .buttonStyle(BessiePrimaryButtonStyle())
                }
            }

            if let pane {
                HStack(spacing: BessieDesign.cardGap) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            AgentStateGlyph(state: AgentSemanticState(herdrValue: pane.agentStatus), size: 6)
                            Text(pane.label ?? pane.title ?? pane.agent ?? "Untitled pane")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            if let controller { PaneControllerStatusLabel(controller: controller) }
                            else { Text("CONNECTING").font(.system(size: 9, design: .monospaced)).foregroundStyle(BessieDesign.subtle) }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(BessieDesign.panel)
                        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

                        if let controller {
                            RecoverableTerminalSurface(controller: controller, fontSize: terminalFontSize)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(BessieDesign.code)
                        }

                        HStack(spacing: 8) {
                            TextField(pane.agent == nil ? "Send input" : "Send a prompt", text: $prompt)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, design: .monospaced))
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(BessieDesign.inset)
                                .overlay { RoundedRectangle(cornerRadius: BessieDesign.controlRadius).stroke(BessieDesign.border, lineWidth: 1) }
                                .onSubmit(sendInput)
                            Button("Send", action: sendInput)
                                .buttonStyle(BessiePrimaryButtonStyle())
                                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller?.acceptsInput != true)
                        }
                        .padding(9)
                        .background(BessieDesign.panel)
                        .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: BessieDesign.paneRadius))
                    .overlay { RoundedRectangle(cornerRadius: BessieDesign.paneRadius).stroke(BessieDesign.border, lineWidth: 1) }

                    agentWorkbench(pane)
                        .frame(width: 470)
                }
                .padding(BessieDesign.cardGap)
            } else {
                ProductEmptyState(symbol: "terminal", title: "No agent selected", detail: "Choose an agent from The herd.", action: nil)
            }
        }
        .task(id: followContextSignature) {
            registry.synchronize(visiblePaneIDs: Set(pane.map { [$0.id] } ?? []), endpoint: endpoint)
            if let pane {
                followFiles.configure(connection: model.activeConnection, projection: projection, paneID: pane.id)
            } else {
                followFiles.stop()
            }
        }
        .onAppear { selectedPaneID = pane?.id }
        .onDisappear { followFiles.stop() }
        .sheet(item: $editor) { ProductEditorSheet(editor: $0) { action in model.perform(action); editor = nil } }
    }

    private func agentWorkbench(_ pane: PaneProjection) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Workbench", selection: $workbenchSection) {
                    ForEach(WorkbenchSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(BessieDesign.panel)
            .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

            switch workbenchSection {
            case .details:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        workbenchRow("NAME", pane.label ?? pane.title ?? pane.agent ?? "Untitled pane")
                        workbenchRow("TYPE", pane.agent.map { "Agent · \($0)" } ?? "Shell")
                        workbenchRow("STATE", AgentSemanticState(herdrValue: pane.agentStatus).title)
                        workbenchRow("WORKSPACE", workspace?.label ?? "Unavailable")
                        workbenchRow("TAB", tab?.label ?? "Unavailable")
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .changes:
                FollowFilesSurface(model: followFiles)
            }
        }
        .background(BessieDesign.panel)
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.cardRadius))
        .overlay { RoundedRectangle(cornerRadius: BessieDesign.cardRadius).stroke(BessieDesign.border, lineWidth: 1) }
    }

    private func workbenchRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(BessieDesign.faint)
            Text(value).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(BessieDesign.strong).textSelection(.enabled)
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }

    private func sendInput() {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let controller, controller.acceptsInput else { return }
        controller.session.sendInput(Data(value.utf8))
        try? controller.inputRouter.send(.keys(["enter"]))
        prompt = ""
    }
}

private struct WorkspacesSurface: View {
    @ObservedObject var model: ConnectionViewModel
    let projection: HerdrSessionProjection
    let open: (String) -> Void
    @State private var editor: ProductEditor?
    @State private var closeWorkspace: WorkspaceProjection?

    private var summaries: [WorkspaceSurfaceSummary] { BessieSurfaceProjection(projection: projection).workspaces }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: "Workspaces") {
                Button("New workspace", systemImage: "plus") { editor = .createWorkspace }
                    .buttonStyle(ProductPrimaryButton())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if summaries.isEmpty {
                        ProductEmptyState(
                            symbol: "square.grid.2x2",
                            title: "No workspaces yet",
                            detail: "Create one to open your first shell."
                        ) { editor = .createWorkspace }
                    } else {
                        VStack(spacing: 7) {
                            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, item in
                                Button { model.perform(.workspaceFocus(id: item.id)) { _ in open(item.id) } } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: item.focused ? "folder.fill" : "folder")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundStyle(item.focused ? BessieDesign.strong : BessieDesign.subtle)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(spacing: 7) {
                                                Text(item.label)
                                                    .font(.system(size: 13, weight: .medium))
                                                if item.attentionCount > 0 {
                                                    HStack(spacing: 5) {
                                                        AgentStateGlyph(state: .blocked, size: 6)
                                                        Text("needs you")
                                                    }
                                                    .productTag()
                                                    .foregroundStyle(BessieDesign.strong)
                                                }
                                            }
                                            Text("\(item.tabCount) tab\(item.tabCount == 1 ? "" : "s") · \(item.paneCount) pane\(item.paneCount == 1 ? "" : "s")")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(BessieDesign.subtle)
                                        }
                                        Spacer()
                                        Text("Open")
                                            .font(.system(size: 11, weight: .medium))
                                            .padding(.horizontal, 10)
                                            .frame(height: 26)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                                    .stroke(BessieDesign.border, lineWidth: 1)
                                            }
                                        Menu {
                                            Button("Rename") { editor = .renameWorkspace(id: item.id, value: item.label) }
                                            Button("Move up") { model.perform(.workspaceMove(id: item.id, insertIndex: max(0, index - 1))) }.disabled(index == 0)
                                            Button("Move down") { model.perform(.workspaceMove(id: item.id, insertIndex: min(summaries.count - 1, index + 1))) }.disabled(index == summaries.count - 1)
                                            Divider()
                                            Button("Close workspace", role: .destructive) { closeWorkspace = projection.workspaces.first { $0.id == item.id } }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .frame(width: 24, height: 24)
                                                .foregroundStyle(BessieDesign.subtle)
                                        }
                                        .menuStyle(.borderlessButton)
                                        .accessibilityLabel("Workspace actions")
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 62)
                                    .background(BessieDesign.panel)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                            .stroke(BessieDesign.border, lineWidth: 1)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(BessieDesign.strong)
                                .draggable(BessieDragPayload.workspace(id: item.id).encoded) {
                                    Text(item.label)
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 12)
                                        .frame(height: 30)
                                        .background(BessieDesign.panel)
                                        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                                }
                                .dropDestination(for: String.self) { values, _ in
                                    handleWorkspaceDrop(values, over: item.id)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 34)
                .padding(.bottom, 60)
            }
            .background(Color.clear)
        }
        .sheet(item: $editor) { ProductEditorSheet(editor: $0) { action in model.perform(action); editor = nil } }
        .confirmationDialog("Close workspace?", isPresented: Binding(get: { closeWorkspace != nil }, set: { if !$0 { closeWorkspace = nil } }), titleVisibility: .visible) {
            if let item = closeWorkspace { Button("Close \(item.label)", role: .destructive) { model.perform(.workspaceClose(id: item.id)); closeWorkspace = nil } }
            Button("Cancel", role: .cancel) { closeWorkspace = nil }
        } message: {
            Text(closeWorkspace.map { projection.confirmationForClosingWorkspace(id: $0.id).message } ?? "")
        }
    }

    private func handleWorkspaceDrop(_ values: [String], over targetID: String) -> Bool {
        guard !model.actionInFlight,
              let value = values.first,
              let payload = BessieDragPayload(encoded: value),
              let action = BessieReorderDrop.workspaceAction(payload: payload, over: targetID, projection: projection)
        else { return false }
        model.perform(action)
        return true
    }
}

private struct WorkspaceSurface: View {
    @ObservedObject var model: ConnectionViewModel
    let projection: HerdrSessionProjection
    let endpoint: HerdrTerminalEndpoint
    @ObservedObject var registry: TerminalControllerRegistry
    @Binding var selectedWorkspaceID: String?
    @Binding var selectedPaneID: String?
    let paneGap: Double
    let terminalFontSize: Double
    @State private var editor: ProductEditor?
    @State private var pendingClose: PendingClose?
    @State private var showNewProcess = false

    private var workspace: WorkspaceProjection? {
        projection.workspaces.first { $0.id == selectedWorkspaceID } ?? projection.focusedWorkspace ?? projection.workspaces.first
    }
    private var tabs: [TabProjection] { projection.tabs.filter { $0.workspaceID == workspace?.id } }
    private var tab: TabProjection? { tabs.first { $0.focused } ?? tabs.first }
    private var visiblePaneIDs: Set<String> { tab.flatMap { projection.layouts[$0.id] }.map { Set($0.root.paneIDs) } ?? [] }
    private var targetPaneID: String? {
        BessiePaneActionTarget.resolve(
            selectedPaneID: selectedPaneID,
            visiblePaneIDs: visiblePaneIDs,
            projection: projection
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(
                crumbs: [workspace?.label].compactMap { $0 },
                title: tab?.label ?? "Workspace"
            ) {
                if model.actionInFlight { ProgressView().controlSize(.small) }
                if let targetPaneID {
                    Menu {
                        Button("Split down") { model.perform(.paneSplit(targetPaneID: targetPaneID, direction: .down, ratio: 0.5, cwd: nil, focus: true)) }
                        Button("Split right") { model.perform(.paneSplit(targetPaneID: targetPaneID, direction: .right, ratio: 0.5, cwd: nil, focus: true)) }
                        Button("Zoom pane") { model.perform(.paneZoom(id: targetPaneID, mode: .toggle)) }
                        if let choices = PaneMoveChoices(projection: projection, paneID: targetPaneID) {
                            PaneMoveMenuItems(paneID: targetPaneID, choices: choices) { model.perform($0) }
                        }
                    } label: {
                        Label("Pane actions", systemImage: "ellipsis.circle")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .foregroundStyle(BessieDesign.text)
                            .background(BessieDesign.panel)
                            .overlay {
                                RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                    .stroke(BessieDesign.border, lineWidth: 1)
                            }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if workspace != nil {
                    Button("New pane", systemImage: "plus") { showNewProcess = true }
                        .buttonStyle(ProductPrimaryButton())
                }
                Menu {
                    if let tab {
                        Button("Rename tab") { editor = .renameTab(id: tab.id, value: tab.label) }
                        Button("Close tab", role: .destructive) { pendingClose = .tab(tab.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundStyle(BessieDesign.subtle)
                        .frame(width: 27, height: 27)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Tab actions")
            }

            HStack(spacing: 2) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, item in
                    Button { model.perform(.tabFocus(id: item.id)); selectedPaneID = nil } label: {
                        HStack(spacing: 7) {
                            AgentStateGlyph(state: AgentSemanticState(herdrValue: item.agentStatus), size: 6)
                            Text(item.label).lineLimit(1)
                            Text("\(item.paneCount)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(BessieDesign.faint)
                        }
                        .font(.system(size: 11, weight: item.id == tab?.id ? .medium : .regular))
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .foregroundStyle(item.id == tab?.id ? BessieDesign.strong : BessieDesign.text)
                        .background(item.id == tab?.id ? BessieDesign.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename") { editor = .renameTab(id: item.id, value: item.label) }
                        Button("Move left") { model.perform(.tabMove(id: item.id, insertIndex: max(0, index - 1))) }.disabled(index == 0)
                        Button("Move right") { model.perform(.tabMove(id: item.id, insertIndex: min(tabs.count - 1, index + 1))) }.disabled(index == tabs.count - 1)
                        Divider()
                        Button("Close tab", role: .destructive) { pendingClose = .tab(item.id) }
                    }
                    .draggable(BessieDragPayload.tab(id: item.id, workspaceID: item.workspaceID).encoded) {
                        Text(item.label)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(BessieDesign.panel)
                            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                    }
                    .dropDestination(for: String.self) { values, _ in
                        handleTabDrop(values, over: item.id, workspaceID: item.workspaceID)
                    }
                }
                Button { if let workspace { model.perform(.tabCreate(workspaceID: workspace.id, cwd: nil, label: nil, focus: true)) } } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BessieDesign.subtle)
                .accessibilityLabel("New tab")
                Spacer()
                Text("\(visiblePaneIDs.count) PANE\(visiblePaneIDs.count == 1 ? "" : "S")")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                    .padding(.trailing, 11)
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(BessieDesign.background)
            .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

            if let tab, let layout = projection.layouts[tab.id] {
                ProductPaneLayout(
                    node: layout.root,
                    tabID: tab.id,
                    panes: projection.panes,
                    selectedPaneID: $selectedPaneID,
                    registry: registry,
                    gap: paneGap,
                    terminalFontSize: terminalFontSize,
                    dividerEnabled: !layout.zoomed && !model.actionInFlight,
                    focus: { model.perform(.paneFocus(id: $0)) },
                    edit: { editor = $0 },
                    action: { model.perform($0) },
                    moveChoices: { PaneMoveChoices(projection: projection, paneID: $0) },
                    close: { pendingClose = .pane($0) }
                )
                .padding(paneGap)
            } else {
                ProductEmptyState(
                    symbol: "rectangle.split.3x1",
                    title: "No panes in this tab",
                    detail: "Add a pane to get started.",
                    actionTitle: "New pane",
                    action: workspace == nil ? nil : { showNewProcess = true }
                )
                    .padding(7)
            }
        }
        .foregroundStyle(ProductPalette.strong)
        .background(Color.clear)
        .task(id: visiblePaneIDs.sorted().joined(separator: ",")) { registry.synchronize(visiblePaneIDs: visiblePaneIDs, endpoint: endpoint) }
        .onAppear {
            selectedWorkspaceID = workspace?.id
            selectedPaneID = targetPaneID
            if ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased() == "new-process" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showNewProcess = true
                }
            }
        }
        .onChange(of: workspace?.id) { _, _ in selectedPaneID = targetPaneID }
        .onChange(of: tab?.id) { _, _ in selectedPaneID = targetPaneID }
        .sheet(item: $editor) { ProductEditorSheet(editor: $0) { action in model.perform(action); editor = nil } }
        .sheet(isPresented: $showNewProcess) {
            if let workspace {
                NewProcessSheet(
                    catalog: model.agentCatalog,
                    catalogLoaded: model.catalogLoaded,
                    startsInAgentMode: false,
                    workspaceID: workspace.id,
                    targetPaneID: targetPaneID,
                    existingNames: Set(projection.panes.compactMap { $0.label ?? $0.agent })
                ) { placement, process in
                    model.launch(placement: placement, process: process) { result in selectedPaneID = result.paneID }
                    showNewProcess = false
                }
            }
        }
        .confirmationDialog(pendingClose?.title ?? "Close?", isPresented: Binding(get: { pendingClose != nil }, set: { if !$0 { pendingClose = nil } }), titleVisibility: .visible) {
            if let pendingClose { Button(pendingClose.buttonTitle, role: .destructive) { model.perform(pendingClose.action); self.pendingClose = nil } }
            Button("Cancel", role: .cancel) { pendingClose = nil }
        } message: { Text(pendingClose?.message(in: projection) ?? "") }
    }

    private func handleTabDrop(_ values: [String], over targetID: String, workspaceID: String) -> Bool {
        guard !model.actionInFlight,
              let value = values.first,
              let payload = BessieDragPayload(encoded: value),
              let action = BessieReorderDrop.tabAction(
                payload: payload,
                over: targetID,
                workspaceID: workspaceID,
                projection: projection
              )
        else { return false }
        model.perform(action)
        return true
    }
}

private enum NewProcessPlacementChoice: String, CaseIterable, Identifiable {
    case splitRight = "Split right"
    case splitDown = "Split down"
    case newTab = "New tab"
    var id: String { rawValue }
}

private struct NewProcessSheet: View {
    let catalog: AgentCatalog
    let catalogLoaded: Bool
    let startsInAgentMode: Bool
    let workspaceID: String
    let targetPaneID: String?
    let existingNames: Set<String>
    let submit: (NewProcessPlacement, NewProcessChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var agentMode = false
    @State private var selectedKind: String?
    @State private var name = ""
    @State private var directory = NSHomeDirectory()
    @State private var arguments = ""
    @State private var placement: NewProcessPlacementChoice = .splitRight

    private var selectedAgent: AgentCatalogItem? { catalog.items.first { $0.kind == selectedKind } }
    private var canSubmit: Bool {
        let placementValid = placement == .newTab || targetPaneID != nil
        return placementValid && (!agentMode || selectedAgent?.availability.isAvailable == true)
    }

    var body: some View {
        ZStack {
            BessieCowprintTexture(base: BessieDesign.background, crop: .newProcess)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    BessieLogoMark(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("New pane")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(BessieDesign.strong)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 27, height: 27)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BessieDesign.subtle)
                    .background(BessieDesign.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                            .stroke(BessieDesign.border, lineWidth: 1)
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 18)
                .frame(height: 60)
                .background(BessieDesign.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        BessieSectionLabel("TYPE")
                        Picker("Type", selection: $agentMode) {
                            Text("Shell").tag(false)
                            Text("Agent").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)

                        if agentMode {
                            BessieSectionLabel("AGENTS")
                                .padding(.top, 5)
                            if catalog.items.isEmpty {
                                if catalogLoaded {
                                    Text("No agents available")
                                        .font(.system(size: 11))
                                        .foregroundStyle(BessieDesign.subtle)
                                } else {
                                    ProgressView("Loading agents…")
                                        .font(.system(size: 11))
                                        .controlSize(.small)
                                }
                            } else {
                                ScrollView {
                                    VStack(spacing: 6) {
                                        ForEach(catalog.items, id: \.kind) { item in
                                            Button {
                                                selectedKind = item.kind
                                                if name.isEmpty { name = AgentSemanticName.unique(kind: item.kind, existing: existingNames) }
                                            } label: {
                                                HStack(spacing: 10) {
                                                    AgentStateGlyph(state: item.availability.isAvailable ? .idle : .unknown, size: 7)
                                                    VStack(alignment: .leading, spacing: 3) {
                                                        Text(item.displayName)
                                                            .font(.system(size: 12.5, weight: .medium))
                                                            .foregroundStyle(BessieDesign.strong)
                                                        Text(item.availability.detail)
                                                            .font(.system(size: 9.5, design: .monospaced))
                                                            .foregroundStyle(BessieDesign.subtle)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                    if selectedKind == item.kind {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundStyle(BessieDesign.strong)
                                                    }
                                                }
                                                .padding(.horizontal, 10)
                                                .frame(height: 52)
                                                .background(selectedKind == item.kind ? BessieDesign.selected : BessieDesign.panel)
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                                        .stroke(selectedKind == item.kind ? BessieDesign.strong.opacity(0.55) : BessieDesign.border, lineWidth: 1)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!item.availability.isAvailable)
                                            .opacity(item.availability.isAvailable ? 1 : 0.56)
                                        }
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(18)
                    .frame(width: 290, alignment: .topLeading)
                    .background(BessieDesign.rail)

                    Rectangle().fill(BessieDesign.border).frame(width: 1)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            BessieSectionLabel("OPTIONS")

                            if agentMode {
                                BessieLabeledInput(label: "Name (optional)") {
                                    TextField("agent-name", text: $name)
                                        .bessieInput()
                                }
                                BessieLabeledInput(label: "Arguments", hint: "One argument per line") {
                                    TextField("--flag", text: $arguments, axis: .vertical)
                                        .lineLimit(3...5)
                                        .bessieInput()
                                }
                            }

                            BessieLabeledInput(label: "Working directory") {
                                TextField("~/code/project", text: $directory)
                                    .bessieInput()
                            }

                            BessieLabeledInput(label: "Placement", hint: targetPaneID == nil ? "A new tab is required because no pane is selected." : nil) {
                                Picker("Placement", selection: $placement) {
                                    ForEach(NewProcessPlacementChoice.allCases) { choice in
                                        Text(choice.rawValue).tag(choice).disabled(targetPaneID == nil && choice != .newTab)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }


                        }
                        .padding(22)
                    }
                }

                HStack(spacing: 8) {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(BessieSecondaryButtonStyle())
                    Button(agentMode ? "Start agent" : "Open shell") { submitLaunch() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(BessiePrimaryButtonStyle())
                        .disabled(!canSubmit)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(BessieDesign.panel)
                .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
            }
        }
        .frame(width: 760, height: agentMode ? 600 : 360)
        .preferredColorScheme(.dark)
        .background(BessieWindowSnapshotProbe(role: "sheet"))
        .onAppear {
            agentMode = startsInAgentMode
            if targetPaneID == nil { placement = .newTab }
            if let item = catalog.items.first(where: { $0.availability.isAvailable }) {
                selectedKind = item.kind
                name = AgentSemanticName.unique(kind: item.kind, existing: existingNames)
            }
        }
    }

    private func submitLaunch() {
        let launchPlacement: NewProcessPlacement?
        switch placement {
        case .splitRight: launchPlacement = targetPaneID.map { .split(targetPaneID: $0, direction: .right, cwd: directory) }
        case .splitDown: launchPlacement = targetPaneID.map { .split(targetPaneID: $0, direction: .down, cwd: directory) }
        case .newTab: launchPlacement = .newTab(workspaceID: workspaceID, cwd: directory)
        }
        guard let launchPlacement else { return }
        let process: NewProcessChoice
        if agentMode, let kind = selectedKind {
            let semanticName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? AgentSemanticName.unique(kind: kind, existing: existingNames) : name
            let args = arguments.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
            process = .agent(kind: kind, name: semanticName, args: args, timeoutMilliseconds: 30_000)
        } else {
            process = .shell
        }
        submit(launchPlacement, process)
    }
}

private struct ProductPaneLayout: View {
    let node: RecursivePaneLayout
    let tabID: String
    let panes: [PaneProjection]
    @Binding var selectedPaneID: String?
    @ObservedObject var registry: TerminalControllerRegistry
    let gap: Double
    let terminalFontSize: Double
    let dividerEnabled: Bool
    let focus: (String) -> Void
    let edit: (ProductEditor) -> Void
    let action: (HerdrAction) -> Void
    let moveChoices: (String) -> PaneMoveChoices?
    let close: (String) -> Void

    var body: some View {
        switch node {
        case .pane(let leaf):
            ProductPane(
                leaf: leaf,
                pane: panes.first { $0.id == leaf.paneID },
                index: panes.firstIndex { $0.id == leaf.paneID }.map { $0 + 1 },
                selected: selectedPaneID == leaf.paneID,
                controller: registry.controllers[leaf.paneID],
                terminalFontSize: terminalFontSize,
                select: { selectedPaneID = leaf.paneID; focus(leaf.paneID) },
                moveChoices: moveChoices(leaf.paneID),
                edit: edit, action: action, close: close
            )
        case .split(let branch):
            ProductSplitBranch(
                branch: branch,
                tabID: tabID,
                panes: panes,
                selectedPaneID: $selectedPaneID,
                registry: registry,
                gap: gap,
                terminalFontSize: terminalFontSize,
                dividerEnabled: dividerEnabled,
                focus: focus,
                edit: edit,
                action: action,
                moveChoices: moveChoices,
                close: close
            )
        }
    }
}

private struct ProductSplitBranch: View {
    let branch: PaneLayoutBranch
    let tabID: String
    let panes: [PaneProjection]
    @Binding var selectedPaneID: String?
    @ObservedObject var registry: TerminalControllerRegistry
    let gap: Double
    let terminalFontSize: Double
    let dividerEnabled: Bool
    let focus: (String) -> Void
    let edit: (ProductEditor) -> Void
    let action: (HerdrAction) -> Void
    let moveChoices: (String) -> PaneMoveChoices?
    let close: (String) -> Void

    @State private var previewRatio: Double?
    @State private var dragOrigin: Double?
    @State private var pendingCommit: UUID?
    @State private var hovering = false

    private var ratio: Double { previewRatio ?? branch.ratio }
    private var dividerExtent: CGFloat { max(1, CGFloat(gap)) }

    var body: some View {
        GeometryReader { proxy in
            let axisExtent = branch.direction == .right ? proxy.size.width : proxy.size.height
            let contentExtent = max(0, axisExtent - dividerExtent)
            if branch.direction == .right {
                HStack(spacing: 0) {
                    child(branch.first)
                        .frame(width: contentExtent * ratio)
                        .frame(maxHeight: .infinity)
                    divider(contentExtent: contentExtent)
                    child(branch.second)
                        .frame(width: contentExtent * (1 - ratio))
                        .frame(maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    child(branch.first)
                        .frame(height: contentExtent * ratio)
                        .frame(maxWidth: .infinity)
                    divider(contentExtent: contentExtent)
                    child(branch.second)
                        .frame(height: contentExtent * (1 - ratio))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: branch.ratio) { _, _ in previewRatio = nil; dragOrigin = nil; pendingCommit = nil }
        .onChange(of: branch.path) { _, _ in previewRatio = nil; dragOrigin = nil; pendingCommit = nil }
    }

    private func child(_ node: RecursivePaneLayout) -> some View {
        ProductPaneLayout(
            node: node,
            tabID: tabID,
            panes: panes,
            selectedPaneID: $selectedPaneID,
            registry: registry,
            gap: gap,
            terminalFontSize: terminalFontSize,
            dividerEnabled: dividerEnabled,
            focus: focus,
            edit: edit,
            action: action,
            moveChoices: moveChoices,
            close: close
        )
    }

    private func divider(contentExtent: CGFloat) -> some View {
        Rectangle()
            .fill(hovering || dragOrigin != nil ? BessieDesign.strong.opacity(0.62) : BessieDesign.border)
            .frame(
                width: branch.direction == .right ? dividerExtent : nil,
                height: branch.direction == .down ? dividerExtent : nil
            )
            .contentShape(Rectangle().inset(by: -4))
            .onHover { inside in
                hovering = inside
                if inside && dividerEnabled {
                    (branch.direction == .right ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(dragGesture(contentExtent: contentExtent), including: dividerEnabled ? .all : .none)
            .accessibilityLabel("Resize split")
            .accessibilityHint("Drag to resize both panes")
    }

    private func dragGesture(contentExtent: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? branch.ratio
                if dragOrigin == nil { dragOrigin = origin; pendingCommit = nil }
                let translation = branch.direction == .right ? value.translation.width : value.translation.height
                previewRatio = BessieSplitDrag.ratio(
                    original: origin,
                    translation: Double(translation),
                    extent: Double(contentExtent)
                )
            }
            .onEnded { value in
                let origin = dragOrigin ?? branch.ratio
                let translation = branch.direction == .right ? value.translation.width : value.translation.height
                let finalRatio = BessieSplitDrag.ratio(
                    original: origin,
                    translation: Double(translation),
                    extent: Double(contentExtent)
                )
                previewRatio = finalRatio
                dragOrigin = nil
                let commit = UUID()
                pendingCommit = commit
                action(.setSplitRatio(tabID: tabID, path: branch.path, ratio: finalRatio))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if pendingCommit == commit {
                        previewRatio = nil
                        pendingCommit = nil
                    }
                }
            }
    }
}

private struct ProductPane: View {
    let leaf: PaneLayoutLeaf
    let pane: PaneProjection?
    let index: Int?
    let selected: Bool
    let controller: PaneTerminalController?
    let terminalFontSize: Double
    let select: () -> Void
    let moveChoices: PaneMoveChoices?
    let edit: (ProductEditor) -> Void
    let action: (HerdrAction) -> Void
    let close: (String) -> Void
    @State private var confirmingTakeover = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 8) {
                    Text(index.map(String.init) ?? "·")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.subtle)
                    AgentStateGlyph(state: AgentSemanticState(herdrValue: pane?.agentStatus ?? "unknown"), size: 6)
                    Text(pane?.label ?? pane?.title ?? pane?.agent ?? "Untitled pane")
                        .font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(pane?.agent ?? "Shell")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(ProductPalette.subtle)
                        .lineLimit(1)
                    Spacer()
                    if let controller {
                        PaneControllerStatusLabel(controller: controller)
                    } else {
                        Text("CONNECTING")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(ProductPalette.subtle)
                    }
                    Menu { paneMenu } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                        .menuStyle(.borderlessButton)
                        .accessibilityLabel("Pane actions")
                }
                .padding(.leading, 9)
                .padding(.trailing, 6)
                .frame(height: 27)
                .background(selected ? ProductPalette.selected : ProductPalette.panel)
                .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
            }
            .buttonStyle(.plain).foregroundStyle(ProductPalette.text)
            if let controller {
                RecoverableTerminalSurface(controller: controller, fontSize: terminalFontSize)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(BessieDesign.code)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.paneRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BessieDesign.paneRadius)
                .stroke(selected ? ProductPalette.strong : ProductPalette.border, lineWidth: selected ? 1 : 1)
        }
        .shadow(color: selected ? BessieDesign.accentSoft : .clear, radius: 0, x: 0, y: 0)
        .contextMenu { paneMenu }
        .alert("Take over this pane?", isPresented: $confirmingTakeover) {
            Button("Cancel", role: .cancel) {}
            Button("Take over", role: .destructive) { controller?.takeOver() }
        } message: {
            Text("The other terminal client will lose control of this pane.")
        }
    }

    @ViewBuilder private var paneMenu: some View {
        Button("Focus") { select() }
        Button("Split right") { action(.paneSplit(targetPaneID: leaf.paneID, direction: .right, ratio: 0.5, cwd: nil, focus: true)) }
        Button("Split down") { action(.paneSplit(targetPaneID: leaf.paneID, direction: .down, ratio: 0.5, cwd: nil, focus: true)) }
        Button("Zoom") { action(.paneZoom(id: leaf.paneID, mode: .toggle)) }
        Menu("Resize pane") {
            Button("Left") { action(.paneResize(id: leaf.paneID, direction: .left, amount: 0.05)) }
            Button("Right") { action(.paneResize(id: leaf.paneID, direction: .right, amount: 0.05)) }
            Button("Up") { action(.paneResize(id: leaf.paneID, direction: .up, amount: 0.05)) }
            Button("Down") { action(.paneResize(id: leaf.paneID, direction: .down, amount: 0.05)) }
        }
        if let moveChoices {
            PaneMoveMenuItems(paneID: leaf.paneID, choices: moveChoices, action: action)
        }
        if controller?.sessionMode == .observe, controller?.hasReadyFrame == true {
            Divider()
            Button("Take over terminal control") { confirmingTakeover = true }
        }
        Button("Rename") { edit(.renamePane(id: leaf.paneID, value: pane?.label ?? "")) }
        Divider()
        Button("Close pane", role: .destructive) { close(leaf.paneID) }
    }
}

private struct PaneMoveMenuItems: View {
    let paneID: String
    let choices: PaneMoveChoices
    let action: (HerdrAction) -> Void

    var body: some View {
        Menu("Move to tab") {
            ForEach(choices.tabs) { choice in
                Button(choice.title) { move(to: choice.destination) }
            }
            if !choices.tabs.isEmpty { Divider() }
            Button("New tab") { move(to: choices.newTab) }
        }
        Menu("Move to workspace") {
            ForEach(choices.workspaces) { choice in
                Button(choice.title) { move(to: choice.destination) }
            }
            if !choices.workspaces.isEmpty { Divider() }
            Button("New workspace") { move(to: choices.newWorkspace) }
        }
    }

    private func move(to destination: PaneMoveDestination) {
        action(.paneMove(id: paneID, destination: destination, focus: true))
    }
}

private struct RecoverableTerminalSurface: View {
    @ObservedObject var controller: PaneTerminalController
    let fontSize: Double
    @State private var confirmingTakeover = false

    var body: some View {
        ZStack {
            GhosttyPaneSurface(controller: controller, fontSize: fontSize)
                .background(BessieDesign.code)
            recoveryOverlay
        }
        .alert("Take over this pane?", isPresented: $confirmingTakeover) {
            Button("Cancel", role: .cancel) {}
            Button("Take over", role: .destructive) { controller.takeOver() }
        } message: {
            Text("The other terminal client will lose control of this pane.")
        }
    }

    @ViewBuilder private var recoveryOverlay: some View {
        switch controller.status {
        case .ownershipConflict:
            terminalMessage(
                title: "Pane is already in use",
                detail: "Another terminal client controls this pane."
            ) {
                Button("Observe") { controller.observe() }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Take over") { confirmingTakeover = true }
                    .buttonStyle(BessiePrimaryButtonStyle())
            }
        case .failed:
            terminalMessage(title: "Terminal unavailable", detail: "Bessie couldn't open this terminal.") {
                Button("Try again") { controller.retry() }
                    .buttonStyle(BessiePrimaryButtonStyle())
            }
        case .stopped:
            terminalMessage(title: "Terminal stopped", detail: "The terminal connection is closed.") {
                Button("Try again") { controller.retry() }
                    .buttonStyle(BessiePrimaryButtonStyle())
            }
        default:
            EmptyView()
        }
    }

    private func terminalMessage<Actions: View>(
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BessieDesign.strong)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(BessieDesign.subtle)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) { actions() }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BessieDesign.code.opacity(0.94))
    }
}

private struct AttentionSurface: View {
    let items: [AttentionSurfaceItem]
    let open: (String) -> Void
    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: "Attention") {}

            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    if !items.isEmpty {
                        HStack(spacing: 7) {
                            Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BessieDesign.subtle)
                        .padding(.bottom, 2)
                    }

                    if items.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 17, weight: .regular))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("You're all caught up.")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(BessieDesign.strong)
                            }
                            Spacer()
                        }
                        .padding(15)
                        .background(BessieDesign.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                .stroke(BessieDesign.border, lineWidth: 1)
                        }
                    } else {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    AgentStateGlyph(state: item.state, size: 9)
                                    Text(item.identity)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(BessieDesign.strong)
                                    Spacer()
                                    Text(item.state.title.uppercased())
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(item.state == .blocked ? BessieDesign.strong : BessieDesign.subtle)
                                }
                                Text(item.location)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(BessieDesign.subtle)
                                HStack(spacing: 7) {
                                    Spacer()
                                    if item.state == .blocked {
                                        Button("Open pane") { open(item.paneID) }
                                            .buttonStyle(ProductPrimaryButton())
                                    } else {
                                        Button("Open pane") { open(item.paneID) }
                                            .buttonStyle(BessieSecondaryButtonStyle())
                                    }
                                }
                            }
                            .padding(15)
                            .background(BessieDesign.panel)
                            .overlay {
                                RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                    .stroke(item.state == .blocked ? BessieDesign.strong.opacity(0.55) : BessieDesign.border, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                        }
                    }


                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 26)
                .padding(.bottom, 60)
            }
        }
    }
}

private enum ProductEditor: Identifiable {
    case createWorkspace
    case renameWorkspace(id: String, value: String)
    case renameTab(id: String, value: String)
    case renamePane(id: String, value: String)
    var id: String { switch self { case .createWorkspace: "create"; case .renameWorkspace(let id, _): "workspace-\(id)"; case .renameTab(let id, _): "tab-\(id)"; case .renamePane(let id, _): "pane-\(id)" } }
}

private struct ProductEditorSheet: View {
    let editor: ProductEditor
    let submit: (HerdrAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var directory = NSHomeDirectory()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 20, weight: .medium))
            if case .createWorkspace = editor {
                TextField("Directory", text: $directory).textFieldStyle(.roundedBorder)
                TextField("Optional label", text: $label).textFieldStyle(.roundedBorder)
            } else {
                TextField("Name", text: $label).textFieldStyle(.roundedBorder)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button(editor.actionTitle) { submit(action); dismiss() }.keyboardShortcut(.defaultAction).disabled(editor.requiresLabel && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
        .padding(24).frame(width: 430)
        .onAppear { label = editor.initialValue }
    }
    private var title: String { switch editor { case .createWorkspace: "Create workspace"; case .renameWorkspace: "Rename workspace"; case .renameTab: "Rename tab"; case .renamePane: "Rename pane" } }
    private var action: HerdrAction {
        switch editor {
        case .createWorkspace: .workspaceCreate(cwd: directory, label: label.isEmpty ? nil : label, focus: true)
        case .renameWorkspace(let id, _): .workspaceRename(id: id, label: label)
        case .renameTab(let id, _): .tabRename(id: id, label: label)
        case .renamePane(let id, _): .paneRename(id: id, label: label.isEmpty ? nil : label)
        }
    }
}

private extension ProductEditor {
    var initialValue: String { switch self { case .createWorkspace: ""; case .renameWorkspace(_, let value), .renameTab(_, let value), .renamePane(_, let value): value } }
    var requiresLabel: Bool { switch self { case .renameWorkspace, .renameTab: true; default: false } }
    var actionTitle: String { switch self { case .createWorkspace: "Create"; default: "Save" } }
}

private enum PendingClose {
    case workspace(String), tab(String), pane(String)
    var action: HerdrAction { switch self { case .workspace(let id): .workspaceClose(id: id); case .tab(let id): .tabClose(id: id); case .pane(let id): .paneClose(id: id) } }
    var title: String { switch self { case .workspace: "Close workspace?"; case .tab: "Close tab?"; case .pane: "Close pane?" } }
    var buttonTitle: String { switch self { case .workspace: "Close workspace"; case .tab: "Close tab"; case .pane: "Close pane" } }
    func message(in projection: HerdrSessionProjection) -> String { switch self { case .workspace(let id): projection.confirmationForClosingWorkspace(id: id).message; case .tab(let id): projection.confirmationForClosingTab(id: id).message; case .pane(let id): projection.confirmationForClosingPane(id: id).message } }
}

private struct ProductSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ProductPalette.faint) }
}

private struct ProductEmptyState: View {
    let symbol: String, title: String, detail: String
    let actionTitle: String
    let action: (() -> Void)?

    init(symbol: String, title: String, detail: String, actionTitle: String = "Create workspace", action: (() -> Void)?) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28, weight: .thin)).foregroundStyle(ProductPalette.faint)
            Text(title).font(.system(size: 15, weight: .medium))
            if !detail.isEmpty {
                Text(detail).font(.system(size: 12)).foregroundStyle(ProductPalette.subtle).multilineTextAlignment(.center).frame(maxWidth: 430)
            }
            if let action { Button(actionTitle, action: action).buttonStyle(ProductPrimaryButton()).padding(.top, 4) }
        }
        .frame(maxWidth: .infinity, minHeight: 250).background(ProductPalette.panel)
        .overlay { Rectangle().stroke(ProductPalette.border, lineWidth: 1) }
    }
}

private struct ProductPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BessiePrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

private struct AgentStateGlyph: View {
    let state: AgentSemanticState
    var size: Double = 9
    var body: some View {
        Group {
            switch state {
            case .blocked:
                Circle()
                    .stroke(ProductPalette.blocked, lineWidth: 1.5)
                    .background(Circle().fill(BessieDesign.background))
            case .done:
                Circle()
                    .stroke(ProductPalette.strong, lineWidth: 1.4)
                    .overlay { Circle().fill(ProductPalette.strong).padding(size * 0.28) }
            case .working:
                Circle().fill(BessieDesign.running)
            case .idle:
                Circle().fill(ProductPalette.faint)
            case .unknown:
                Circle().stroke(ProductPalette.faint, lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(state.title)
    }
}

private struct BessieProductMark: View {
    var body: some View { BessieBrandMark() }
}


private enum ProductPalette {
    static let background = BessieDesign.background
    static let rail = BessieDesign.rail
    static let panel = BessieDesign.panel
    static let strong = BessieDesign.strong
    static let text = BessieDesign.text
    static let subtle = BessieDesign.subtle
    static let faint = BessieDesign.faint
    static let border = BessieDesign.border
    static let selected = BessieDesign.selected
    static let blocked = BessieDesign.blocked
    static let ink = BessieDesign.accentForeground
}

private extension AgentSemanticState {
    var title: String { switch self { case .blocked: "needs you"; case .working: "working"; case .done: "done"; case .idle: "idle"; case .unknown: "status unknown" } }
}

private extension AgentAvailability {
    var detail: String {
        switch self {
        case .available: "Available"
        case .unavailable(let reason): reason
        }
    }
}

private struct PaneControllerStatusLabel: View {
    @ObservedObject var controller: PaneTerminalController

    var body: some View {
        Text(controller.sessionMode == .observe && controller.hasReadyFrame ? "READ ONLY" : controller.status.productLabel)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(ProductPalette.subtle)
    }
}

private extension TerminalControllerStatus {
    var productLabel: String { switch self { case .starting: "STARTING"; case .waitingForFull: "SYNCING"; case .ready: "LIVE"; case .reconnecting: "RECONNECTING"; case .ownershipConflict: "IN USE"; case .stopped: "STOPPED"; case .failed: "FAILED" } }
}

private extension View {
    func productTag() -> some View { self.font(.system(size: 8, weight: .bold)).padding(.horizontal, 5).frame(height: 16).overlay { Rectangle().stroke(ProductPalette.border, lineWidth: 1) }.foregroundStyle(ProductPalette.subtle) }
}
