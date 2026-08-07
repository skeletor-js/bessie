import AppKit
import BessieCore
import Combine
import SwiftUI

enum ProductDestination: String, CaseIterable, Identifiable {
    case herd = "The herd"
    case workspaces = "All Workspaces"
    case tabs = "All Tabs"
    case projects = "Projects"
    case workspace = "Workspace"
    case files = "Files"
    case agent = "Agent"
    case settings = "Settings"
    static func visible(flags: BessieFeatureFlags) -> [ProductDestination] {
        flags.isEnabled(.fileBrowserEditor) ? [.herd, .projects, .files] : [.herd, .projects]
    }
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .herd: "circle.grid.3x3"
        case .workspaces: "square.grid.2x2"
        case .tabs: "rectangle.stack"
        case .projects: "folder.badge.gearshape"
        case .workspace: "rectangle.split.3x1"
        case .files: "folder"
        case .agent: "terminal"
        case .settings: "gearshape"
        }
    }

    static func initial(flags: BessieFeatureFlags) -> ProductDestination {
        guard let raw = ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased() else { return .herd }
        if raw == "new-process" { return .workspace }
        if raw == "herd" { return .herd }
        if raw == "agent-detail" { return .agent }
        if raw == "project-capture" { return .projects }
        if raw == "command-palette" { return .workspace }
        let destination = ProductDestination.allCases.first { $0.rawValue.lowercased() == raw } ?? .herd
        return destination == .files && !flags.isEnabled(.fileBrowserEditor) ? .herd : destination
    }

    static func navigationTarget(for command: BessieShortcutCommand) -> ProductDestination? {
        command == .projectsPicker ? .projects : nil
    }

    static func global(for section: WorkspaceHierarchySection) -> ProductDestination {
        switch section {
        case .herd: .herd
        case .workspace: .workspaces
        case .tab: .tabs
        }
    }
}

enum BessieActiveConnectionSelection {
    static func shouldRestore(selectedConnectionID: String?, activeConnectionID: String) -> Bool {
        selectedConnectionID != activeConnectionID
    }
}

struct ProductNavigationRequest: Equatable {
    let connectionID: String
    let workspaceID: String
    let tabID: String
    let paneID: String

    func target(connectionID: String, projection: HerdrSessionProjection) -> PaneOpenTarget? {
        guard self.connectionID == connectionID,
              projection.workspaces.contains(where: { $0.id == workspaceID }),
              projection.tabs.contains(where: { $0.id == tabID && $0.workspaceID == workspaceID }),
              projection.panes.contains(where: {
                  $0.id == paneID && $0.workspaceID == workspaceID && $0.tabID == tabID
              })
        else { return nil }
        return PaneOpenTarget(workspaceID: workspaceID, tabID: tabID, paneID: paneID)
    }
}

extension RoutedPaneTarget {
    func currentTarget(
        connectionID: String,
        projection: HerdrSessionProjection
    ) -> PaneOpenTarget? {
        guard self.connectionID == connectionID,
              projection.workspaces.contains(where: { $0.id == workspaceID }),
              projection.tabs.contains(where: { $0.id == tabID && $0.workspaceID == workspaceID }),
              projection.panes.contains(where: {
                  $0.id == paneID && $0.workspaceID == workspaceID && $0.tabID == tabID
              })
        else { return nil }
        return PaneOpenTarget(workspaceID: workspaceID, tabID: tabID, paneID: paneID)
    }

    func isAuthoritativelyFocused(
        connectionID: String,
        projection: HerdrSessionProjection
    ) -> Bool {
        currentTarget(connectionID: connectionID, projection: projection) != nil
            && projection.focusedWorkspace?.id == workspaceID
            && projection.focusedTab?.id == tabID
            && projection.focusedPane?.id == paneID
    }
}

struct BessieCloseReconciliation: Equatable {
    let connectionID: String
    let workspaceID: String?
    let paneID: String?
    let destination: ProductDestination
    let exitsZen: Bool

    init(
        connectionID: String,
        projection: HerdrSessionProjection,
        preferredWorkspaceID: String?
    ) {
        let fallback = projection.focusFallback(preferredWorkspaceID: preferredWorkspaceID)
        self.connectionID = connectionID
        workspaceID = fallback.workspaceID
        paneID = fallback.paneID
        destination = fallback.workspaceID == nil ? .herd : .workspace
        exitsZen = fallback.workspaceID == nil
    }
}

struct ConnectionTopologyProjection {
    let connection: BessieConnectionDefinition
    let projection: HerdrSessionProjection
}

struct TopologyWorkspaceID: Hashable {
    let connectionID: String
    let workspaceID: String
}

struct TopologyTabID: Hashable {
    let connectionID: String
    let tabID: String
}

struct TopologyPaneID: Hashable {
    let connectionID: String
    let paneID: String
}

struct ScopedWorkspaceItem: Identifiable {
    let id: TopologyWorkspaceID
    let connection: BessieConnectionDefinition
    let summary: WorkspaceSurfaceSummary
}

struct ScopedTabItem: Identifiable {
    let id: TopologyTabID
    let tab: TabProjection
}

struct ScopedPaneItem: Identifiable {
    let id: TopologyPaneID
    let pane: PaneProjection
}

struct ScopedTopologyProjection {
    let connections: [ConnectionTopologyProjection]
    let workspaces: [ScopedWorkspaceItem]
    let tabs: [ScopedTabItem]
    let panes: [ScopedPaneItem]

    init(connections: [ConnectionTopologyProjection], scope: ConnectionScope) {
        self.connections = connections.filter { item in
            switch scope {
            case .all: true
            case .connection(let id): item.connection.id == id
            }
        }
        workspaces = self.connections.flatMap { item in
            let summaries = Dictionary(uniqueKeysWithValues: BessieSurfaceProjection(projection: item.projection).workspaces.map { ($0.id, $0) })
            return item.projection.workspaces.compactMap { workspace in
                summaries[workspace.id].map {
                    ScopedWorkspaceItem(
                        id: .init(connectionID: item.connection.id, workspaceID: workspace.id),
                        connection: item.connection,
                        summary: $0
                    )
                }
            }
        }
        tabs = self.connections.flatMap { item in
            item.projection.tabs.map {
                ScopedTabItem(
                    id: .init(connectionID: item.connection.id, tabID: $0.id),
                    tab: $0
                )
            }
        }
        panes = self.connections.flatMap { item in
            item.projection.panes.map {
                ScopedPaneItem(
                    id: .init(connectionID: item.connection.id, paneID: $0.id),
                    pane: $0
                )
            }
        }
    }

    func openTarget(for id: TopologyPaneID) -> RoutedPaneTarget? {
        guard let pane = panes.first(where: { $0.id == id })?.pane else { return nil }
        return RoutedPaneTarget(
            connectionID: id.connectionID,
            workspaceID: pane.workspaceID,
            tabID: pane.tabID,
            paneID: pane.id
        )
    }

    func openTarget(for id: TopologyTabID) -> RoutedPaneTarget? {
        guard let tab = tabs.first(where: { $0.id == id })?.tab else { return nil }
        let candidates = panes.filter {
            $0.id.connectionID == id.connectionID && $0.pane.tabID == id.tabID
        }
        guard let pane = candidates.first(where: { $0.pane.focused })?.pane
                ?? candidates.first?.pane
        else { return nil }
        return RoutedPaneTarget(
            connectionID: id.connectionID,
            workspaceID: tab.workspaceID,
            tabID: tab.id,
            paneID: pane.id
        )
    }
}

enum WorkspaceScope: Equatable {
    case selectedTab(connectionID: String, workspaceID: String, tabID: String)
    case allTabs(connectionID: String, workspaceID: String)
    case allWorkspaces(connectionID: String)
    case allHerds
}

enum WorkspaceScopeReducer {
    static func selectingAll(_ section: WorkspaceHierarchySection, connectionID: String, workspaceID: String) -> WorkspaceScope {
        switch section {
        case .herd: .allHerds
        case .workspace: .allWorkspaces(connectionID: connectionID)
        case .tab: .allTabs(connectionID: connectionID, workspaceID: workspaceID)
        }
    }

    static func selectingSidebarPane(
        _ target: RoutedPaneTarget,
        preserving scope: WorkspaceScope?
    ) -> WorkspaceScope {
        scope ?? .selectedTab(
            connectionID: target.connectionID,
            workspaceID: target.workspaceID,
            tabID: target.tabID
        )
    }

    static func filtered(_ projection: HerdRailProjection, scope: WorkspaceScope) -> HerdRailProjection {
        switch scope {
        case .selectedTab(let connectionID, let workspaceID, let tabID):
            projection.filtered(connectionID: connectionID, workspaceID: workspaceID, tabID: tabID)
        case .allTabs(let connectionID, let workspaceID):
            projection.filtered(connectionID: connectionID, workspaceID: workspaceID)
        case .allWorkspaces(let connectionID):
            projection.filtered(connectionID: connectionID, workspaceID: nil)
        case .allHerds:
            projection.filtered(connectionID: nil, workspaceID: nil)
        }
    }

    static func selection(
        in projection: HerdRailProjection,
        retaining selected: HerdPaneIdentity?,
        focused: [HerdPaneIdentity]
    ) -> RoutedPaneTarget? {
        if let selected,
           let row = projection.rows.first(where: { $0.id == selected }) {
            return row.target
        }
        for focusedPane in focused {
            if let row = projection.rows.first(where: { $0.id == focusedPane }) {
                return row.target
            }
        }
        return projection.rows.first?.target
    }
}

enum BessieSidebarSection: String, CaseIterable, Identifiable {
    case herd = "The Herd"
    case projects = "Projects"
    case sessions = "Sessions"

    var id: String { rawValue }
    var destination: ProductDestination? {
        switch self {
        case .herd: .herd
        case .projects: .projects
        case .sessions: nil
        }
    }
    var supportsDisclosure: Bool { self == .sessions }
}

enum BessieSidebarAttentionPolicy {
    static func isProminent(needsYouCount: Int) -> Bool { needsYouCount > 0 }
}

enum BessieSidebarSessionSummary {
    static func text(tabCount: Int, paneCount: Int) -> String {
        "\(tabCount) \(tabCount == 1 ? "tab" : "tabs") · \(paneCount) \(paneCount == 1 ? "pane" : "panes")"
    }
}

struct BessieSidebarDisclosureState: Equatable {
    private(set) var collapsed: Set<BessieSidebarSection> = []

    func isExpanded(_ section: BessieSidebarSection) -> Bool { !collapsed.contains(section) }

    mutating func toggle(_ section: BessieSidebarSection) {
        if collapsed.contains(section) { collapsed.remove(section) }
        else { collapsed.insert(section) }
    }
}

enum BessieActionSurfaceContract {
    static let workspaceGroups = [["open", "rename"], ["move-up", "move-down"], ["close"]]
    static let paneGroups = [["focus", "zen"], ["split-right", "split-down", "zoom"], ["resize", "move", "take-over", "rename"], ["close"]]
}

enum BessieZenControlLabels {
    static let expand = "Expand"
}

enum BessieWorkspacePresentationContract {
    static let inCardChromeHeight: CGFloat = 0
}

enum BessieZenPresentationContract {
    static let awarenessRailWidth = BessieDesign.collapsedRailWidth
    static let terminalHeaderHeight: CGFloat = 34
    static let gutter = BessieDesign.cardGap
    static let windowTitle = "zen"

    static func elsewhereLabel(count: Int) -> String? {
        count > 0 ? "\(count) elsewhere" : nil
    }
}

enum BessieAppearanceToggle {
    static func target(current: BessieAppearance, effectiveSystemIsDark: Bool) -> BessieAppearance {
        BessieThemeRegistry.quickToggleTarget(
            for: current,
            systemScheme: effectiveSystemIsDark ? .dark : .light
        )
    }

    static func isVisible(for appearance: BessieAppearance) -> Bool {
        appearance == .system || appearance == .dark || appearance == .light
    }
}

extension RecursivePaneLayout {
    func isolatedPane(_ paneID: String) -> RecursivePaneLayout? {
        switch self {
        case .pane(let leaf):
            leaf.paneID == paneID ? self : nil
        case .split(let branch):
            branch.first.isolatedPane(paneID) ?? branch.second.isolatedPane(paneID)
        }
    }
}

enum TopologyCreation: Equatable {
    case workspace
    case tab(workspaceID: String, name: String)
    case pane(targetPaneID: String, direction: SplitDirection, name: String)

    var action: HerdrAction {
        switch self {
        case .workspace:
            .workspaceCreate(cwd: nil, label: nil, focus: true)
        case .tab(let workspaceID, let name):
            .tabCreate(workspaceID: workspaceID, cwd: nil, label: normalized(name), focus: true)
        case .pane(let targetPaneID, let direction, _):
            .paneSplit(targetPaneID: targetPaneID, direction: direction, ratio: 0.5, cwd: nil, focus: true)
        }
    }

    func followUpAction(createdPaneID: String) -> HerdrAction? {
        guard case .pane(_, _, let name) = self else { return nil }
        return .paneRename(id: createdPaneID, label: normalized(name))
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NamedTopologyRequest: Identifiable, Equatable {
    enum Target: Equatable {
        case tab(connectionID: String, workspaceID: String)
        case pane(connectionID: String, targetPaneID: String, direction: SplitDirection)
        case movedPaneTab(connectionID: String, paneID: String, workspaceID: String)
    }

    let id = UUID()
    let target: Target

    var title: String {
        switch target {
        case .tab: "Name new tab"
        case .pane: "Name new pane"
        case .movedPaneTab: "Name new tab"
        }
    }

    var fieldLabel: String {
        switch target {
        case .tab, .movedPaneTab: "Tab name"
        case .pane: "Pane name"
        }
    }
}

struct BessieProductShell: View {
    @ObservedObject var model: ConnectionViewModel
    @ObservedObject var fleet: ConnectionFleetViewModel
    let projection: HerdrSessionProjection
    let terminalEndpoint: HerdrTerminalEndpoint
    @ObservedObject var terminalRegistry: TerminalControllerRegistry
    @Binding var navigationRequest: ProductNavigationRequest?
    @Binding var zenState: BessieZenPresentationState
    @EnvironmentObject private var settings: BessieSettingsModel
    @EnvironmentObject private var themeCoordinator: BessieThemeCoordinator
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.bessieDensity) private var density
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: ProductDestination = .herd
    @State private var selectedTopologyConnectionID: String?
    /// Workspace open in the main surface.
    @State private var selectedWorkspaceID: String?
    @State private var selectedPaneID: String?
    @State private var workspaceScope: WorkspaceScope?
    @State private var topologySelectionInFlight: UUID?
    @State private var notificationRouteInFlight: UUID?
    @State private var processAutomationStarted = false
    @State private var performanceSwitchAutomationStarted = false
    @State private var themeCaptureAutomationStarted = false
    @StateObject private var shortcuts = BessieKeyboardShortcutCoordinator()
    @StateObject private var commandPalette = BessieCommandPaletteModel()
    @State private var sidebarCollapsed = false
    @State private var isFullScreen = false
    @State private var showCommandPalette = false
    @State private var commandPaletteMRU = CommandPaletteMRU()
    @State private var commandPaletteRetryAttempts: [String: Int] = [:]
    @State private var commandPaletteRebuildPending = false
    @State private var commandPalettePreviousResponder: NSResponder?
    @State private var commandPalettePreviewPending = false
    @State private var isDispatchingPaletteCommand = false
    @State private var shortcutEditor: ProductEditor?
    @State private var namedTopologyRequest: NamedTopologyRequest?
    @State private var shortcutClose: PendingClose?
    @State private var shortcutCloseConnectionID: String?
    @State private var topologyWorkspaceClose: ScopedWorkspaceItem?
    @State private var topologyPaneClose: ScopedPaneItem?
    @State private var topologyPaneTakeover: ScopedPaneItem?
    @State private var openRouteToken: UUID?
    @ObservedObject var projects: ProjectsViewModel
    @ObservedObject var commandPaletteAvailability: BessieCommandPaletteAvailability
    let featureFlags: BessieFeatureFlags
    @State private var railWidth: CGFloat = BessieDesign.railWidth
    @State private var workbenchWidth: CGFloat = 420
    @State private var sidebarDisclosure = BessieSidebarDisclosureState()
    @State private var sidebarHerdFilter: HerdListFilter = .all

    private var surfaces: BessieSurfaceProjection { BessieSurfaceProjection(projection: projection) }
    private var topology: ScopedTopologyProjection {
        ScopedTopologyProjection(connections: fleet.topologyConnections, scope: fleet.herdScope)
    }
    private var freshHierarchyTopology: ScopedTopologyProjection {
        ScopedTopologyProjection(
            connections: fleet.topologyConnections.filter {
                fleet.connectedConnectionIDs.contains($0.connection.id)
            },
            scope: .all
        )
    }
    private var baseHerdRailProjection: HerdRailProjection {
        HerdRailProjection(
            connections: fleet.topologyConnections.map {
                HerdRailConnectionInput(
                    connection: $0.connection,
                    projection: $0.projection,
                    isFresh: fleet.connectedConnectionIDs.contains($0.connection.id)
                )
            },
            scope: fleet.herdScope
        )
    }
    private var effectiveWorkspaceScope: WorkspaceScope? {
        if let workspaceScope { return workspaceScope }
        guard destination == .workspace else { return nil }
        let connectionID = selectedTopologyConnectionID ?? model.activeConnection.id
        guard let workspaceID = selectedWorkspaceID else { return nil }
        let connection = freshHierarchyTopology.connections.first { $0.connection.id == connectionID }
        let selectedTabID = selectedPaneID.flatMap { paneID in
            connection?.projection.panes.first {
                $0.id == paneID && $0.workspaceID == workspaceID
            }?.tabID
        }
        guard let tabID = selectedTabID
                ?? connection?.projection.tabs.first(where: {
                    $0.workspaceID == workspaceID && $0.focused
                })?.id
                ?? connection?.projection.tabs.first(where: { $0.workspaceID == workspaceID })?.id
        else { return nil }
        return .selectedTab(connectionID: connectionID, workspaceID: workspaceID, tabID: tabID)
    }
    private var herdRailProjection: HerdRailProjection {
        guard let scope = effectiveWorkspaceScope else { return baseHerdRailProjection }
        return WorkspaceScopeReducer.filtered(baseHerdRailProjection, scope: scope)
    }
    private var focusedHerdPanes: [HerdPaneIdentity] {
        freshHierarchyTopology.connections.compactMap { item in
            item.projection.focusedPane.map {
                HerdPaneIdentity(connectionID: item.connection.id, paneID: $0.id)
            }
        }
    }
    private var hierarchyHerdRows: [HerdPickerRow] {
        HerdPickerPresentation.hierarchyRows(
            connections: fleet.connectionDefinitions,
            health: fleet.connectionHealth,
            selectedConnectionID: selectedTopologyConnectionID ?? model.activeConnection.id
        )
    }
    private var hierarchyWorkspaceRows: [WorkspacePickerRow] {
        WorkspacePickerPresentation.rows(
            topology: freshHierarchyTopology,
            selectedConnectionID: selectedTopologyConnectionID ?? model.activeConnection.id,
            selectedWorkspaceID: selectedWorkspaceID
        )
    }
    private var hierarchyPresentation: WorkspaceHierarchyPresentation {
        WorkspaceHierarchyPresentation(
            connectionLabel: model.activeConnection.kind == .local
                ? "local"
                : ConnectionDisplayLabel(connection: model.activeConnection).short,
            projection: projection,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedPaneID: selectedPaneID,
            globalSection: effectiveWorkspaceScope?.hierarchySection,
            globalPaneCount: herdRailProjection.rows.count
        )
    }
    private var commandPaletteIndexInput: CommandPaletteIndexInput {
        let topologies = Dictionary(
            fleet.topologyConnections.map { ($0.connection.id, $0.projection) },
            uniquingKeysWith: { first, _ in first }
        )
        let connections = fleet.connectionDefinitions.map { connection in
            let isFresh = fleet.connectedConnectionIDs.contains(connection.id)
            let connectionProjection: HerdrSessionProjection? = isFresh ? topologies[connection.id] : nil
            let workspaceLabels = Dictionary(
                (connectionProjection?.workspaces ?? []).map { ($0.id, $0.label) },
                uniquingKeysWith: { first, _ in first }
            )
            let tabLabels = Dictionary(
                (connectionProjection?.tabs ?? []).map { ($0.id, $0.label) },
                uniquingKeysWith: { first, _ in first }
            )
            let agents = Dictionary(
                (connectionProjection?.agents ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let panesByWorkspace = Dictionary(
                grouping: connectionProjection?.panes ?? [],
                by: \.workspaceID
            )
            let panes = (connectionProjection?.panes ?? []).map { pane in
                let agent = agents[pane.id]
                return CommandPalettePaneInput(
                    id: pane.id,
                    workspaceID: pane.workspaceID,
                    workspaceTitle: workspaceLabels[pane.workspaceID] ?? "Untitled workspace",
                    tabID: pane.tabID,
                    tabTitle: tabLabels[pane.tabID] ?? "Untitled tab",
                    title: pane.presentationTitle,
                    detail: agent?.identity ?? "Shell pane",
                    semanticState: AgentSemanticState(herdrValue: agent?.agentStatus ?? pane.agentStatus),
                    provider: agent?.displayAgent ?? agent?.agent ?? pane.agent,
                    keywords: [agent?.identity, pane.effectiveCWD].compactMap { $0 }
                )
            }
            let workspaces = (connectionProjection?.workspaces ?? []).map { workspace in
                let rolledState = (panesByWorkspace[workspace.id] ?? [])
                    .map { pane in
                        AgentSemanticState(herdrValue: agents[pane.id]?.agentStatus ?? pane.agentStatus)
                    }
                    .min { $0.sortRank < $1.sortRank }
                    ?? AgentSemanticState(herdrValue: workspace.agentStatus)
                return CommandPaletteWorkspaceInput(
                    id: workspace.id,
                    number: workspace.number,
                    title: workspace.label,
                    tabCount: workspace.tabCount,
                    paneCount: workspace.paneCount,
                    semanticState: rolledState
                )
            }
            let healthDetail = isFresh
                ? fleet.statusLabel(connectionID: connection.id)
                : BessieCommandPalette.retryHealthDetail(
                    base: fleet.statusLabel(connectionID: connection.id),
                    attemptCount: commandPaletteRetryAttempts[connection.id, default: 0]
                )
            return CommandPaletteConnectionInput(
                connection: connection,
                freshness: isFresh ? .fresh : .disconnected,
                healthDetail: healthDetail,
                panes: panes,
                workspaces: workspaces
            )
        }
        let projectInputs = projects.projects.map { stored in
            CommandPaletteProjectInput(
                id: stored.project.id,
                title: stored.project.name,
                detail: "Project · \(stored.project.tabs.flatMap(\.panes).count) panes",
                location: stored.project.primaryFolder?.path,
                keywords: [stored.project.projectDescription]
                    + stored.project.folders.flatMap { [$0.name, $0.path] },
                isRunning: projects.runningInstance(for: stored.project.id) != nil
            )
        }
        let selectedConnectionID = selectedTopologyConnectionID ?? fleet.activeConnectionID
        return CommandPaletteIndexInput(
            connections: connections,
            projects: projectInputs,
            commands: BessieKeyboardShortcutRouter.commands,
            context: CommandPaletteIndexContext(
                activeConnectionID: selectedConnectionID,
                scope: fleet.herdScope,
                focusedWorkspaceID: selectedWorkspaceID,
                focusedPaneID: selectedPaneID,
                mru: commandPaletteMRU
            )
        )
    }
    private var canOpenCommandPalette: Bool {
        let window = NSApp.keyWindow
        return BessieCommandPaletteOpenability.allowsOpen(
            onboardingCompleted: settings.onboarding.completed,
            mainWindowIsKey: window?.identifier == BessieWindowCoordinator.mainWindowIdentifier
                && window?.isKeyWindow == true,
            hasAttachedSheet: window?.attachedSheet != nil
        )
    }
    private static let commandPaletteWindowStatePublisher: AnyPublisher<Notification, Never> = {
        Publishers.MergeMany([
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification),
            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification),
        ]).eraseToAnyPublisher()
    }()
    private var topologyIdentitySignature: String {
        topology.connections.flatMap { item in
            item.projection.workspaces.map { "w:\(item.connection.id):\($0.id)" }
                + item.projection.tabs.map { "t:\(item.connection.id):\($0.workspaceID):\($0.id)" }
                + item.projection.panes.map { "p:\(item.connection.id):\($0.workspaceID):\($0.tabID):\($0.id)" }
        }.joined(separator: "|")
    }
    private var herdCounts: [HerdListFilter: Int] {
        HerdListBuilder.counts(
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope
        )
    }
    private var needsYouCards: [HerdCardModel] {
        HerdListBuilder.cards(
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: .all,
            filter: .needsYou
        )
    }
    private var sidebarHerdCards: [HerdCardModel] {
        HerdListBuilder.cards(
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope,
            filter: sidebarHerdFilter
        )
    }
    private var zenPaneID: String? {
        guard zenState.isActive else { return nil }
        if let paneID = zenState.selectedPaneID,
           projection.panes.contains(where: { $0.id == paneID }) {
            return paneID
        }
        return selectedPaneID ?? projection.focusedPane?.id
    }
    private var zenAgentCards: [HerdCardModel] {
        HerdListBuilder.cards(
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope,
            filter: .all
        )
    }
    private var zenSelectedAgentCard: HerdCardModel? {
        guard let paneID = zenPaneID else { return nil }
        return zenAgentCards.first {
            $0.connectionID == model.activeConnection.id && $0.paneTarget.paneID == paneID
        }
    }
    private var zenElsewhereCount: Int {
        BessieZenAgentRouter.needsYouElsewhereCount(
            focused: currentZenTarget,
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope
        )
    }
    private var activeNotificationPaneID: String? {
        guard scenePhase == .active, destination == .workspace || destination == .agent else { return nil }
        guard selectedTopologyConnectionID == nil || selectedTopologyConnectionID == model.activeConnection.id else { return nil }
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
        return "\(notifications.authorizationLoaded)|\(model.activeConnection.id)|\(settings.preferences.notifications.rawValue)|\(scenePhase)|\(activeNotificationPaneID ?? "-")|\(panes)"
    }
    private var notificationRouteSignature: String {
        let pending = notifications.pendingRoute.map {
            "\($0.id.uuidString):\($0.target.connectionID):\($0.target.workspaceID):\($0.target.tabID):\($0.target.paneID)"
        } ?? "-"
        let panes = projection.panes
            .map { "\($0.id):\($0.workspaceID):\($0.tabID)" }
            .sorted()
            .joined(separator: "|")
        return "\(pending)|\(model.activeConnection.id)|\(notificationRouteInFlight?.uuidString ?? "-")|\(panes)"
    }
    private var shortcutContextSignature: String {
        [
            destination.rawValue,
            zenState.isActive ? "zen" : "standard",
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
    private var presentedTerminalPaneIDs: [String] {
        if zenState.isActive { return zenPaneID.map { [$0] } ?? [] }
        switch destination {
        case .workspace:
            let workspace = projection.workspaces.first { $0.id == selectedWorkspaceID }
                ?? projection.focusedWorkspace
                ?? projection.workspaces.first
            let tabs = projection.tabs.filter { $0.workspaceID == workspace?.id }
            let selectedTabID = selectedPaneID.flatMap { paneID in
                projection.panes.first {
                    $0.id == paneID && $0.workspaceID == workspace?.id
                }?.tabID
            }
            let tab = tabs.first { $0.id == selectedTabID }
                ?? tabs.first(where: \.focused)
                ?? tabs.first
            return tab.flatMap { projection.layouts[$0.id]?.root.paneIDs } ?? []
        case .agent:
            return (selectedPaneID ?? projection.focusedPane?.id).map { [$0] } ?? []
        case .herd, .workspaces, .tabs, .projects, .files, .settings:
            return []
        }
    }
    private var prewarmTerminalPaneIDs: [String] {
        let workspaceID = selectedWorkspaceID
            ?? projection.focusedWorkspace?.id
            ?? projection.workspaces.first?.id
        guard let workspaceID else { return [] }
        return projection.panes
            .filter { $0.workspaceID == workspaceID }
            .map(\.id)
    }
    private var terminalRegistrySignature: String {
        let available = projection.panes.map(\.id).sorted().joined(separator: ",")
        return "\(terminalEndpoint.connectionID)|\(terminalEndpoint.executablePath)|\(terminalEndpoint.socketPath)|\(presentedTerminalPaneIDs.joined(separator: ","))|\(prewarmTerminalPaneIDs.joined(separator: ","))|\(available)"
    }

    private var shellPresentation: some View {
        HStack(spacing: 0) {
            productRail
                .frame(width: settings.preferences.railCollapsed ? BessieDesign.collapsedRailWidth : BessieDesign.railWidth)
                .layoutPriority(0)
                .bessieSurface(base: BessieDesign.rail)

            Color.clear
                .frame(width: density.shellPanelGap)
                .allowsHitTesting(false)

            productContent
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .bessieSurface(base: BessieDesign.background)
        }
        .padding(.horizontal, density.shellOutsideInset)
        .padding(.top, isFullScreen ? density.shellOutsideInset : 0)
        .padding(.bottom, density.shellBottomInset)
        .background(Color.clear)
        .foregroundStyle(BessieDesign.text)
        .tint(BessieDesign.strong)
        .allowsHitTesting(!showCommandPalette)
        .accessibilityHidden(showCommandPalette)
        .overlay {
            if showCommandPalette {
                GeometryReader { geometry in
                    ZStack(alignment: .top) {
                        Color.black.opacity(BessieCommandPalette.scrimOpacity)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { commandPalette.dismiss() }
                            .accessibilityElement()
                            .accessibilityLabel("Dismiss command palette")
                            .accessibilityAction(named: "Dismiss") { commandPalette.dismiss() }
                        BessieCommandPalette(
                            model: commandPalette,
                            maxListHeight: geometry.size.height * BessieCommandPalette.maximumListHeightFraction
                        )
                        .padding(.top, geometry.size.height * BessieCommandPalette.topInsetFraction)
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
                    }
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(20)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showCommandPalette)
    }

    private var shellStateLifecycle: some View {
        shellPresentation
        .onAppear(perform: prepareShell)
        .onDisappear {
            shortcuts.stop()
            showCommandPalette = false
            commandPaletteAvailability.canToggle = false
        }
        .onChange(of: model.activeConnection.id) { _, _ in activeConnectionChanged() }
        .onChange(of: fleet.herdScope) { _, scope in
            reconcileSelection(for: scope)
            scheduleCommandPaletteRebuild()
        }
        .onChange(of: topologyIdentitySignature) { _, _ in
            reconcileSelection(for: fleet.herdScope)
            if let workspaceScope { reconcileWorkspaceScopeSelection(workspaceScope) }
        }
        .onChange(of: navigationRequest) { _, request in consumeNavigationRequest(request) }
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
            settings.recordLastWorkspace(id, connectionID: selectedTopologyConnectionID ?? model.activeConnection.id)
        }
        .onChange(of: settings.onboarding.completed) { _, completed in
            if !completed, showCommandPalette { commandPalette.dismiss() }
            refreshCommandPaletteAvailability()
        }
        .onChange(of: fleet.connectedConnectionIDs) { _, connectedIDs in
            for id in connectedIDs { commandPaletteRetryAttempts.removeValue(forKey: id) }
        }
        .onChange(of: zenState.focusIntent) { _, _ in
            if let paneID = zenState.selectedPaneID { focusTerminal(paneID: paneID) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bessieCommand)) { notification in
            if let command = notification.object as? BessieShortcutCommand { handleShortcut(command) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onReceive(Self.commandPaletteWindowStatePublisher) { _ in
            refreshCommandPaletteAvailability()
        }
        .onReceive(fleet.objectWillChange) { _ in
            scheduleCommandPaletteRebuild()
        }
        .onReceive(projects.objectWillChange) { _ in
            scheduleCommandPaletteRebuild()
        }
    }

    private var shellLifecycle: some View {
        shellStateLifecycle
        .task(id: "\(projection.panes.count)-\(model.agentCatalog.items.count)") { runProcessAutomationIfRequested() }
        .task(id: notificationSignature) {
            notifications.reconcile(
                connection: model.activeConnection,
                panes: surfaces.notificationPanes,
                policy: settings.preferences.notifications,
                activePaneID: activeNotificationPaneID
            )
        }
        .task(id: notificationRouteSignature) { routePendingNotification() }
        .task(id: shortcutContextSignature) {
            shortcuts.update(isZenActive: { zenState.isActive }) { command in handleShortcut(command) }
        }
        .task(id: terminalRegistrySignature) {
            terminalRegistry.reconcile(
                presentedPaneIDs: presentedTerminalPaneIDs,
                availablePaneIDs: Set(projection.panes.map(\.id)),
                prewarmPaneIDs: prewarmTerminalPaneIDs,
                endpoint: terminalEndpoint
            )
            runPerformanceSwitchAutomationIfRequested()
            runThemeCaptureAutomationIfRequested()
        }
    }

    var body: some View {
        shellLifecycle
        .sheet(item: $shortcutEditor) { editor in
            ProductEditorSheet(editor: editor) { action in
                model.perform(action)
                shortcutEditor = nil
            }
        }
        .sheet(item: $namedTopologyRequest) { request in
            TopologyNameSheet(request: request) { name in
                performNamedTopologyRequest(request, name: name)
                namedTopologyRequest = nil
            }
        }
        .confirmationDialog(
            shortcutClose?.title ?? "Close?",
            isPresented: Binding(get: { shortcutClose != nil }, set: { if !$0 { cancelShortcutClose() } }),
            titleVisibility: .visible
        ) {
            if let shortcutClose {
                Button(shortcutClose.buttonTitle, role: .destructive) {
                    performConfirmedClose(shortcutClose)
                    self.shortcutClose = nil
                    shortcutCloseConnectionID = nil
                }
            }
            Button("Cancel", role: .cancel) { cancelShortcutClose() }
        } message: { Text(shortcutClose?.message(in: projection) ?? "") }
        .confirmationDialog(
            "Close workspace?",
            isPresented: Binding(
                get: { topologyWorkspaceClose != nil },
                set: { if !$0 { topologyWorkspaceClose = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = topologyWorkspaceClose {
                Button("Close \(item.summary.label)", role: .destructive) { closeTopologyWorkspace(item) }
            }
            Button("Cancel", role: .cancel) { topologyWorkspaceClose = nil }
        } message: {
            Text(topologyWorkspaceClose.map { item in
                topology.connections.first(where: { $0.connection.id == item.id.connectionID })?
                    .projection.confirmationForClosingWorkspace(id: item.id.workspaceID).message
                    ?? "This workspace is no longer available."
            } ?? "")
        }
        .confirmationDialog(
            "Close pane?",
            isPresented: Binding(
                get: { topologyPaneClose != nil },
                set: { if !$0 { topologyPaneClose = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = topologyPaneClose {
                Button("Close \(item.pane.presentationTitle)", role: .destructive) { closeTopologyPane(item) }
            }
            Button("Cancel", role: .cancel) { topologyPaneClose = nil }
        } message: {
            Text(topologyPaneClose.map { item in
                topology.connections.first(where: { $0.connection.id == item.id.connectionID })?
                    .projection.confirmationForClosingPane(id: item.id.paneID).message
                    ?? "This pane is no longer available."
            } ?? "")
        }
        .alert("Take over this pane?", isPresented: Binding(
            get: { topologyPaneTakeover != nil },
            set: { if !$0 { topologyPaneTakeover = nil } }
        )) {
            Button("Cancel", role: .cancel) { topologyPaneTakeover = nil }
            Button("Take over", role: .destructive) {
                topologyPaneController(topologyPaneTakeover)?.takeOver()
                topologyPaneTakeover = nil
            }
        } message: {
            Text("The other terminal client will lose control of this pane.")
        }
        .alert("Action failed", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.clearActionError() } }
        )) {
            Button("OK") { model.clearActionError() }
        } message: { Text(model.actionError ?? "No error details were returned.") }
        .projectConnectionSync(
            model: projects,
            fleet: fleet
        )
        .projectLaunchPresentation(model: projects, navigate: openProjectHandoff)
    }

    private var workspaceHierarchyRail: WorkspaceHierarchyRail {
        WorkspaceHierarchyRail(
            presentation: hierarchyPresentation,
            herds: hierarchyHerdRows,
            workspaces: hierarchyWorkspaceRows,
            collapsed: settings.preferences.railCollapsed,
            mutationsDisabled: model.actionInFlight
                || model.navigationInFlight
                || !fleet.connectedConnectionIDs.contains(model.activeConnection.id),
            expandRail: { settings.preferences.railCollapsed = false },
            showAllHerds: { showGlobalHierarchy(.herd) },
            showAllWorkspaces: { showGlobalHierarchy(.workspace) },
            showAllTabs: { showGlobalHierarchy(.tab) },
            selectHerd: activateHierarchyHerd,
            retryHerd: { fleet.retry(connectionID: $0) },
            addHerd: openConnectionSettings,
            manageHerds: openConnectionSettings,
            openWorkspace: { id in
                guard let item = freshHierarchyTopology.workspaces.first(where: { $0.id == id }) else { return }
                openWorkspace(item)
            },
            renameWorkspace: { row in
                guard let item = freshHierarchyTopology.workspaces.first(where: { $0.id == row.id }) else { return }
                renameWorkspace(item)
            },
            closeWorkspace: { row in
                guard let item = freshHierarchyTopology.workspaces.first(where: { $0.id == row.id }) else { return }
                topologyWorkspaceClose = item
            },
            createWorkspace: createWorkspace,
            focusTab: focusHierarchyTab,
            createTab: createHierarchyTab,
            renameTab: { shortcutEditor = .renameTab(id: $0, value: $1) },
            closeTab: { requestClose(.tab($0)) }
        )
    }

    @ViewBuilder private var productContent: some View {
        switch destination {
        case .herd:
            HerdSurface(
                fleet: fleet,
                openPane: openRoutedPane,
                inspectPane: inspectRoutedPane,
                createWorkspace: createWorkspace,
                openSettings: { destination = .settings }
            )
        case .workspaces:
            GlobalWorkspacesSurface(
                topology: freshHierarchyTopology,
                open: openWorkspace,
                createWorkspace: createWorkspace
            )
        case .tabs:
            GlobalTabsSurface(
                topology: freshHierarchyTopology,
                open: { id in
                    if let target = freshHierarchyTopology.openTarget(for: id) {
                        openRoutedPane(target)
                    }
                },
                createWorkspace: createWorkspace
            )
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
                zenPaneID: zenPaneID,
                paneGap: settings.preferences.paneGap,
                terminalFontSize: settings.preferences.terminalFontSize,
                fileBrowserEnabled: featureFlags.isEnabled(.fileBrowserEditor),
                enterZen: enterZen,
                createWorkspace: createWorkspace,
                requestSplit: requestPaneName,
                requestMoveToNewTab: requestMoveToNewTabName,
                requestClose: requestClose
            )
        case .files:
            WorkspaceFilesSurface(
                connection: model.activeConnection,
                projection: projection,
                selectedWorkspaceID: selectedWorkspaceID,
                selectedPaneID: selectedPaneID,
                remoteFileAccess: model.remoteFileAccess
            )
        case .agent:
            AgentDetailSurface(
                model: model,
                projection: projection,
                endpoint: terminalEndpoint,
                registry: terminalRegistry,
                selectedPaneID: $selectedPaneID,
                terminalFontSize: settings.preferences.terminalFontSize,
                followFilesEnabled: featureFlags.isEnabled(.followFiles),
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
        HerdRail(
            projection: herdRailProjection,
            healthMessages: fleet.connectionIssues.map { "\($0.label): \($0.title)" },
            selectedPane: selectedPaneID.map { HerdPaneIdentity(connectionID: selectedTopologyConnectionID ?? model.activeConnection.id, paneID: $0) },
            hierarchy: workspaceHierarchyRail,
            collapsed: railCollapsedBinding,
            appearance: themeCoordinator.binding(),
            openSearch: { openCommandPalette() },
            selectDestination: { target in
                if zenState.isActive { exitZen() }
                destination = target
            },
            openPane: openSidebarPane,
            enterZen: { openSidebarPane($0, activateZen: true) },
            performPaneAction: { target, action in
                guard let item = scopedPane(for: target) else { return }
                performPaneAction(item, action)
            },
            requestSplit: { target, direction in
                requestPaneName(
                    connectionID: target.connectionID,
                    paneID: target.paneID,
                    direction: direction
                )
            },
            paneMoveChoices: { target in
                scopedPane(for: target).flatMap(topologyPaneMoveChoices)
            },
            requestMoveToNewTab: { target, workspaceID in
                requestMoveToNewTabName(
                    connectionID: target.connectionID,
                    paneID: target.paneID,
                    workspaceID: workspaceID
                )
            },
            canTakeOverPane: { target in
                guard let item = scopedPane(for: target),
                      let controller = topologyPaneController(item)
                else { return false }
                return controller.sessionMode == .observe && controller.hasReadyFrame
            },
            takeOverPane: { target in
                topologyPaneTakeover = scopedPane(for: target)
            },
            renamePane: { target in
                guard let item = scopedPane(for: target) else { return }
                renameTopologyPane(item)
            },
            closePane: { target in
                topologyPaneClose = scopedPane(for: target)
            }
        )
    }

    private var railCollapsedBinding: Binding<Bool> {
        Binding(
            get: { settings.preferences.railCollapsed },
            set: { collapsed in
                if zenState.isActive && !collapsed {
                    exitZen(expandRail: true)
                } else {
                    settings.preferences.railCollapsed = collapsed
                }
            }
        )
    }

    /// Icon-only rail: Bessie cow + destination icons + expand control.
    private var collapsedProductRail: some View {
        let needsYouCount = herdCounts[.needsYou, default: 0]
        return VStack(spacing: 6) {
            Button {
                sidebarCollapsed = false
            } label: {
                BessieLogoMark(width: 26)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Expand sidebar")
            .accessibilityLabel("Expand sidebar")
            .padding(.top, 10)

            Divider().overlay(BessieDesign.border).padding(.horizontal, 10)

            collapsedIconButton(
                destination: .herd,
                symbol: ProductDestination.herd.symbol,
                label: ProductDestination.herd.rawValue,
                selected: destination == .herd || destination == .agent,
                badge: needsYouCount == 0 ? nil : "\(needsYouCount)"
            )
            collapsedIconButton(
                destination: .projects,
                symbol: ProductDestination.projects.symbol,
                label: ProductDestination.projects.rawValue,
                selected: destination == .projects,
                badge: nil
            )
            collapsedSectionButton(section: .sessions, symbol: "rectangle.stack", label: "Sessions")
            if featureFlags.isEnabled(.fileBrowserEditor) {
                collapsedIconButton(
                    destination: .files,
                    symbol: ProductDestination.files.symbol,
                    label: ProductDestination.files.rawValue,
                    selected: destination == .files,
                    badge: nil
                )
            }

            Spacer(minLength: 8)

            collapsedIconButton(
                destination: .settings,
                symbol: ProductDestination.settings.symbol,
                label: ProductDestination.settings.rawValue,
                selected: destination == .settings,
                badge: nil
            )
            collapsedActionButton(
                symbol: effectiveDarkAppearance ? "sun.max" : "moon",
                label: "Switch to \(appearanceToggleTarget.title)",
                action: toggleAppearance
            )
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var expandedProductRail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                BessieProductMark()
                Spacer(minLength: 4)
                Button {
                    sidebarCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BessieDesign.subtle)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Collapse sidebar")
                .accessibilityLabel("Collapse sidebar")
            }
            .padding(.horizontal, 12)
            .padding(.top, 13)
            .padding(.bottom, 8)

            connectionScopeMenu
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    railDestination(.herd)
                    railDestination(.projects)

                    if BessieSidebarAttentionPolicy.isProminent(needsYouCount: herdCounts[.needsYou, default: 0]) {
                        sidebarAttentionHeader(count: herdCounts[.needsYou, default: 0])
                        ForEach(needsYouCards) { card in
                            sidebarAttentionCard(card)
                        }
                    }

                    sidebarSectionHeader(.sessions, trailing: nil, add: createWorkspace, addLabel: "New session")
                    if sidebarDisclosure.isExpanded(.sessions) {
                        ForEach(topology.workspaces) { item in sidebarSessionTree(item) }
                        if topology.workspaces.isEmpty {
                            sidebarEmptyRow("No sessions · Create one", action: createWorkspace)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }

            Divider().overlay(BessieDesign.border)
            HStack(spacing: 2) {
                Button { destination = .settings } label: {
                    railRow(symbol: "gearshape", label: "Settings", end: nil, selected: destination == .settings)
                }
                .buttonStyle(.plain)
                Button { toggleAppearance() } label: {
                    Image(systemName: effectiveDarkAppearance ? "sun.max" : "moon")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Switch to \(appearanceToggleTarget.title)")
                .accessibilityLabel("Switch to \(appearanceToggleTarget.title)")
                .accessibilityValue(effectiveDarkAppearance ? "Dark mode" : "Light mode")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
    }

    private func collapsedIconButton(
        destination target: ProductDestination,
        symbol: String,
        label: String,
        selected: Bool,
        badge: String?
    ) -> some View {
        Button {
            destination = target
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.subtle)
                    .frame(width: 40, height: 36)
                    .background(selected ? BessieDesign.selected : BessieSemanticColor.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .leading) {
                        if selected {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(BessieDesign.accent)
                                .frame(width: 2.5, height: 16)
                                .offset(x: -1)
                        }
                    }

                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(BessieDesign.accentForeground)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(BessieDesign.accent)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -2)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func collapsedActionButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(BessieDesign.subtle)
                .frame(width: 40, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func collapsedSectionButton(
        section: BessieSidebarSection,
        symbol: String,
        label: String
    ) -> some View {
        collapsedActionButton(symbol: symbol, label: label) {
            if !sidebarDisclosure.isExpanded(section) { sidebarDisclosure.toggle(section) }
            sidebarCollapsed = false
        }
    }

    private var effectiveDarkAppearance: Bool {
        BessieThemeRegistry.scheme(
            for: settings.preferences.appearance,
            systemScheme: colorScheme
        ) == .dark
    }

    private var appearanceToggleTarget: BessieThemeID {
        BessieThemeRegistry.quickToggleTarget(
            for: settings.preferences.appearance,
            systemScheme: colorScheme
        )
    }

    private func toggleAppearance() {
        _ = themeCoordinator.requestSelection(BessieAppearanceToggle.target(
            current: settings.preferences.appearance,
            effectiveSystemIsDark: colorScheme == .dark
        ))
    }

    private func sidebarSectionHeader(
        _ section: BessieSidebarSection,
        trailing: String?,
        add: (() -> Void)? = nil,
        addLabel: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            if section.supportsDisclosure {
                Button { sidebarDisclosure.toggle(section) } label: {
                    Image(systemName: sidebarDisclosure.isExpanded(section) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 18, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sidebarDisclosure.isExpanded(section) ? "Collapse" : "Expand") \(section.rawValue)")
            }
            if let target = section.destination {
                Button { destination = target } label: {
                    Text(section.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.45)
                        .foregroundStyle(
                            destination == target || (target == .herd && destination == .agent)
                                ? BessieDesign.strong
                                : BessieDesign.text
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(section.rawValue)")
            } else {
                Button { sidebarDisclosure.toggle(section) } label: {
                    Text(section.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.45)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(section.rawValue), \(sidebarDisclosure.isExpanded(section) ? "expanded" : "collapsed")")
            }
            if let trailing {
                Text(trailing).font(.system(size: 9, design: .monospaced))
            }
            if let add, let addLabel {
                Button(action: add) { Image(systemName: "plus").frame(width: 22, height: 22) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(addLabel)
            }
        }
        .foregroundStyle(BessieDesign.faint)
        .padding(.horizontal, 9)
        .padding(.top, section == .herd ? 2 : 13)
        .frame(minHeight: 28)
    }

    private func sidebarFilterButton(_ filter: HerdListFilter) -> some View {
        Button { sidebarHerdFilter = filter } label: {
            Text(filter.rawValue)
                .font(.system(size: 9.5, weight: sidebarHerdFilter == filter ? .semibold : .regular))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(sidebarHerdFilter == filter ? BessieDesign.selected : BessieSemanticColor.clear)
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(filter.rawValue) agents")
    }

    @ViewBuilder
    private func sidebarSessionTree(_ item: ScopedWorkspaceItem) -> some View {
        let selected = (destination == .workspace || destination == .agent)
            && item.id.connectionID == selectedTopologyConnectionID
            && item.id.workspaceID == selectedWorkspaceID
        VStack(alignment: .leading, spacing: 1) {
            Button { openWorkspace(item) } label: {
                HStack(spacing: 9) {
                    AgentStateGlyph(state: item.summary.rolledState, size: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspaceLabel(item))
                            .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                            .foregroundStyle(BessieDesign.strong)
                            .lineLimit(1)
                        Text(BessieSidebarSessionSummary.text(
                            tabCount: item.summary.tabCount,
                            paneCount: item.summary.paneCount
                        ))
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(BessieDesign.faint)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(BessieDesign.faint)
                }
                .padding(.horizontal, 9)
                .frame(minHeight: 42)
                .background(selected ? BessieDesign.selected.opacity(0.62) : BessieSemanticColor.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.summary.label) session, \(item.summary.tabCount) tabs, \(item.summary.paneCount) panes")
            .contextMenu {
                Button("Open session") { openWorkspace(item) }
                Button("Rename") { renameWorkspace(item) }
                Divider()
                Button("Close session", role: .destructive) { topologyWorkspaceClose = item }
            }

            if selected {
                ForEach(scopedCurrentPanes(connectionID: item.id.connectionID)) { pane in
                    sidebarNestedPane(pane)
                }
            }
        }
    }

    private func sidebarNestedPane(_ item: ScopedPaneItem) -> some View {
        let selected = item.id.connectionID == selectedTopologyConnectionID && selectedPaneID == item.pane.id
        return Button {
            if let target = topology.openTarget(for: item.id) { openRoutedPane(target) }
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(selected ? BessieDesign.accent : BessieSemanticColor.clear)
                    .frame(width: 2, height: 22)
                AgentStateGlyph(state: AgentSemanticState(herdrValue: item.pane.agentStatus), size: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.pane.presentationTitle)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.text)
                        .lineLimit(1)
                    Text(sidebarPaneMetadata(item))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(BessieDesign.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 2)
            }
            .padding(.leading, 15)
            .padding(.trailing, 8)
            .frame(minHeight: 35)
            .background(selected ? BessieDesign.selected : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.pane.presentationTitle) pane, \(sidebarPaneMetadata(item))")
        .contextMenu { sidebarPaneMenu(item) }
    }

    private func sidebarPaneMetadata(_ item: ScopedPaneItem) -> String {
        let tab = topology.tabs.first { $0.id.connectionID == item.id.connectionID && $0.tab.id == item.pane.tabID }?.tab.label
        let folder = item.pane.effectiveCWD.map { URL(fileURLWithPath: $0).lastPathComponent }
        let values = [tab, folder].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return values.isEmpty ? "Terminal" : values.joined(separator: " · ")
    }

    private func sidebarAttentionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Text("NEEDS YOU")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(BessieDesign.strong)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(BessieDesign.code)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(BessieDesign.strong)
                .clipShape(Capsule())
            Spacer()
            Button("View all") { destination = .herd }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(BessieDesign.subtle)
        }
        .padding(.horizontal, 9)
        .padding(.top, 14)
        .padding(.bottom, 5)
    }

    private func sidebarAttentionCard(_ card: HerdCardModel) -> some View {
        Button { openRoutedPane(card.paneTarget) } label: {
            HStack(alignment: .top, spacing: 8) {
                AgentStateGlyph(state: card.state, size: 7)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.identity)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BessieDesign.strong)
                        .lineLimit(1)
                    Text(card.location)
                        .font(.system(size: 9.5))
                        .foregroundStyle(BessieDesign.subtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(BessieDesign.faint)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(BessieDesign.selected.opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(BessieDesign.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 3)
        .accessibilityLabel("Open \(card.identity), needs you, \(card.location)")
    }

    private func sidebarEmptyRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(BessieDesign.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(minHeight: density.rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private func sidebarPaneMenu(_ item: ScopedPaneItem) -> some View {
        let controller = topologyPaneController(item)
        PaneContextMenuContent(
            paneID: item.pane.id,
            primaryTitle: "Open pane",
            primaryAction: {
                if let target = topology.openTarget(for: item.id) { openRoutedPane(target) }
            },
            zenTitle: "Open in Zen",
            enterZen: {
                if let target = topology.openTarget(for: item.id) { openRoutedPane(target, activateZen: true) }
            },
            action: { performPaneAction(item, $0) },
            requestSplit: { direction in
                requestPaneName(connectionID: item.id.connectionID, paneID: item.pane.id, direction: direction)
            },
            moveChoices: topologyPaneMoveChoices(item),
            requestMoveToNewTab: { workspaceID in
                requestMoveToNewTabName(
                    connectionID: item.id.connectionID,
                    paneID: item.pane.id,
                    workspaceID: workspaceID
                )
            },
            canTakeOver: controller?.sessionMode == .observe && controller?.hasReadyFrame == true,
            requestTakeover: { topologyPaneTakeover = item },
            rename: { renameTopologyPane(item) },
            close: { topologyPaneClose = item }
        )
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

    @ViewBuilder private func railDestination(_ item: ProductDestination, label: String? = nil) -> some View {
        let needsYouCount = herdCounts[.needsYou, default: 0]
        Button { destination = item } label: {
            railRow(
                symbol: item.symbol,
                label: label ?? item.rawValue,
                end: item == .herd && needsYouCount > 0
                    ? "\(needsYouCount)"
                    : nil,
                selected: destination == item || (item == .herd && destination == .agent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? item.rawValue)
    }

    private func railGroupLabel(
        _ text: String,
        action: (() -> Void)?,
        accessibilityLabel: String?
    ) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(BessieDesign.faint)
            Spacer()
            if let action, let accessibilityLabel {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BessieDesign.subtle)
                .accessibilityLabel(accessibilityLabel)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
    }

    private var paneGroupLabel: some View {
        HStack(spacing: 4) {
            Text("PANES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(BessieDesign.faint)
            Spacer()
            paneCreationMenu
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
    }

    private var paneCreationMenu: some View {
        Menu {
            Button("Split right") {
                if let pane = scopedTargetPane { requestPaneName(pane.pane.id, direction: .right) }
            }
            Button("Split down") {
                if let pane = scopedTargetPane { requestPaneName(pane.pane.id, direction: .down) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(BessieDesign.subtle)
        .disabled(scopedTargetPane == nil)
        .accessibilityLabel("New pane")
    }

    private var connectionScopeMenu: some View {
        Menu {
            Button {
                fleet.setScope(.all)
            } label: {
                if fleet.herdScope == .all { Label("All", systemImage: "checkmark") }
                else { Text("All") }
            }
            Divider()
            ForEach(fleet.connectionDefinitions) { connection in
                Button {
                    fleet.setScope(.connection(id: connection.id))
                } label: {
                    let title = connection.kind == .local
                        ? "Local"
                        : ConnectionDisplayLabel(connection: connection).short
                    let status = fleet.statusLabel(connectionID: connection.id)
                    if fleet.herdScope == .connection(id: connection.id) {
                        Label("\(title) · \(status)", systemImage: "checkmark")
                    } else {
                        Text("\(title) · \(status)")
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                Text(fleet.scopeLabel)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(BessieDesign.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(BessieDesign.text)
            .padding(.horizontal, 9)
            .frame(height: density.rowHeight)
            .background(BessieDesign.inset)
            .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Connection filter, \(fleet.scopeLabel)")
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
                    .foregroundStyle(BessieDesign.faint)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: density.rowHeight)
        .foregroundStyle(selected ? BessieDesign.strong : BessieDesign.text)
        .background(selected ? BessieDesign.selected : BessieSemanticColor.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private func openRoutedPane(_ routed: RoutedPaneTarget) {
        openRoutedPane(routed, activateZen: false)
    }

    private func openSidebarPane(_ routed: RoutedPaneTarget) {
        openSidebarPane(routed, activateZen: false)
    }

    private func openSidebarPane(_ routed: RoutedPaneTarget, activateZen: Bool) {
        let preservedScope = WorkspaceScopeReducer.selectingSidebarPane(
            routed,
            preserving: effectiveWorkspaceScope
        )
        openRoutedPane(
            routed,
            activateZen: activateZen,
            preservingSidebarScope: preservedScope
        )
    }

    @discardableResult
    private func dispatchPaletteRoute(_ route: CommandPaletteRouteIntent) -> Bool {
        switch route {
        case .pane(let connectionID, let workspaceID, let tabID, let paneID):
            let target = RoutedPaneTarget(connectionID: connectionID, workspaceID: workspaceID, tabID: tabID, paneID: paneID)
            guard freshHierarchyTopology.openTarget(
                for: .init(connectionID: connectionID, paneID: paneID)
            ) == target else {
                reportStalePaletteTarget()
                return false
            }
            openRoutedPane(target)
            return true
        case .workspace(let connectionID, let workspaceID):
            guard let item = freshHierarchyTopology.workspaces.first(where: {
                $0.id == .init(connectionID: connectionID, workspaceID: workspaceID)
            }) else {
                reportStalePaletteTarget()
                return false
            }
            if zenState.isActive { exitZen() }
            openWorkspace(item)
            return true
        case .project(let projectID):
            guard projects.projects.contains(where: { $0.project.id == projectID }) else {
                reportStalePaletteTarget()
                return false
            }
            if zenState.isActive { exitZen() }
            guard projects.launchImmediately(projectID) else {
                fleet.reportRouteFailure(projects.openUnavailableReason(for: projectID))
                return false
            }
            return true
        case .connection(let connectionID):
            guard fleet.connectionDefinitions.contains(where: { $0.id == connectionID }) else {
                reportStalePaletteTarget()
                return false
            }
            if zenState.isActive { exitZen() }
            if !fleet.connectedConnectionIDs.contains(connectionID) {
                commandPaletteRetryAttempts[connectionID, default: 0] += 1
                fleet.retry(connectionID: connectionID)
            } else {
                _ = fleet.activate(connectionID: connectionID)
            }
            selectedTopologyConnectionID = connectionID
            fleet.setScope(.connection(id: connectionID))
            destination = .herd
            return true
        case .command(let command):
            if model.actionInFlight,
               ![.showCommandPalette, .showHerd, .showSettings, .projectsPicker,
                 .workspacePicker, .openNextNeedsYou, .toggleSidebar, .toggleZen, .exitZen].contains(command) {
                fleet.reportRouteFailure("That command cannot run while another Herdr action is in flight.")
                return false
            }
            if let failure = paletteCommandContextFailure(command) {
                fleet.reportRouteFailure(failure)
                return false
            }
            if zenState.isActive, paletteCommandExitsZen(command) { exitZen() }
            isDispatchingPaletteCommand = true
            defer { isDispatchingPaletteCommand = false }
            handleShortcut(command)
            return true
        }
    }

    private func reportStalePaletteTarget() {
        fleet.reportRouteFailure("That palette target is no longer available in the current Herdr state.")
    }

    private func openCommandPalette(initialQuery: String = "") {
        guard !showCommandPalette, canOpenCommandPalette else {
            refreshCommandPaletteAvailability()
            return
        }
        let window = NSApp.keyWindow
        commandPalettePreviousResponder = window?.firstResponder
        window?.makeFirstResponder(nil)
        commandPalette.open(input: commandPaletteIndexInput, initialQuery: initialQuery)
        shortcuts.enterCommandPalette(
            isSearchFocused: { commandPalette.isSearchFocused },
            bufferPrintableCharacters: { commandPalette.bufferPrintableCharacters($0) },
            handle: handleCommandPaletteKeyAction
        )
        showCommandPalette = true
        refreshCommandPaletteAvailability()
    }

    private func closeCommandPalette(restoreFocus: Bool) {
        showCommandPalette = false
        shortcuts.exitCommandPalette()
        let previousResponder = commandPalettePreviousResponder
        commandPalettePreviousResponder = nil
        refreshCommandPaletteAvailability()
        if restoreFocus, let previousResponder, let window = NSApp.keyWindow {
            DispatchQueue.main.async { window.makeFirstResponder(previousResponder) }
        }
    }

    private func handleCommandPaletteKeyAction(_ action: CommandPaletteKeyboard.Action) {
        switch action {
        case .ignore:
            break
        case .moveSelection(let delta):
            commandPalette.moveSelection(by: delta)
        case .activate(let alternate):
            commandPalette.activate(alternate: alternate)
        case .dismiss:
            commandPalette.dismiss()
        }
    }

    private func paletteCommandExitsZen(_ command: BessieShortcutCommand) -> Bool {
        switch command {
        case .showHerd, .showSettings, .newProject, .projectsPicker, .workspacePicker:
            true
        default:
            false
        }
    }

    private func paletteCommandContextFailure(_ command: BessieShortcutCommand) -> String? {
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
        case .renameWorkspace, .closeWorkspace, .newTab:
            return workspace == nil ? "That command needs a current Herdr workspace." : nil
        case .renameTab, .previousTab, .nextTab, .closeTab:
            return tab == nil ? "That command needs a current Herdr tab." : nil
        case .renamePane, .previousPane, .nextPane, .swapPane, .splitPane,
             .closePane, .zoomPane, .resizePane:
            return paneID == nil ? "That command needs a current Herdr pane." : nil
        case .focusPane(let direction):
            guard let paneID, let tab, let layout = projection.layouts[tab.id],
                  BessiePaneNavigation.target(from: paneID, direction: direction, in: layout.root) != nil
            else { return "There is no pane in that direction." }
            return nil
        case .previousRailPane, .nextRailPane:
            return herdRailProjection.rows.isEmpty ? "There are no fresh Herdr panes to open." : nil
        case .toggleZen:
            return !zenState.isActive && paneID == nil ? "Zen needs a current Herdr pane." : nil
        case .exitZen:
            return zenState.isActive ? nil : "Zen is not active."
        case .previousAgent, .nextAgent:
            return fleet.agents.isEmpty ? "There are no fresh Herdr agents to open." : nil
        default:
            return nil
        }
    }

    private func refreshCommandPaletteAvailability() {
        let canToggle = canOpenCommandPalette
        if commandPaletteAvailability.canToggle != canToggle {
            commandPaletteAvailability.canToggle = canToggle
        }
        guard commandPalettePreviewPending, canOpenCommandPalette else { return }
        commandPalettePreviewPending = false
        let initialQuery = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "07" ? "sch" : ""
        openCommandPalette(initialQuery: initialQuery)
    }

    private func awaitCommandPalettePreviewWindow(remainingAttempts: Int = 100) {
        guard commandPalettePreviewPending, remainingAttempts > 0 else { return }
        refreshCommandPaletteAvailability()
        guard commandPalettePreviewPending else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            awaitCommandPalettePreviewWindow(remainingAttempts: remainingAttempts - 1)
        }
    }

    private func scheduleCommandPaletteRebuild() {
        guard showCommandPalette, !commandPaletteRebuildPending else { return }
        commandPaletteRebuildPending = true
        DispatchQueue.main.async {
            commandPaletteRebuildPending = false
            guard showCommandPalette else { return }
            commandPalette.rebuild(input: commandPaletteIndexInput)
        }
    }

    private func openRoutedPane(
        _ routed: RoutedPaneTarget,
        activateZen: Bool,
        preservingSidebarScope: WorkspaceScope? = nil
    ) {
        guard let targetModel = fleet.activate(connectionID: routed.connectionID) else {
            model.reportRouteFailure(
                "Couldn't open this pane because its Herdr connection is unavailable. Reconnect it, then try again from The herd."
            )
            destination = .herd
            return
        }
        guard let current = targetModel.projection,
              let target = routed.currentTarget(
                  connectionID: targetModel.activeConnection.id,
                  projection: current
              )
        else {
            targetModel.reportRouteFailure(
                "Couldn't open this pane because its Herdr location is no longer current. Refresh The herd and try again."
            )
            destination = .herd
            return
        }

        presentRoutedPane(
            routed,
            projection: current,
            model: targetModel,
            activateZen: activateZen,
            preservingSidebarScope: preservingSidebarScope
        )
        if routed.isAuthoritativelyFocused(connectionID: targetModel.activeConnection.id, projection: current) { return }

        let token = UUID()
        openRouteToken = token
        targetModel.openPane(target) { fresh in
            guard openRouteToken == token,
                  fleet.activeConnectionID == routed.connectionID
            else { return }
            presentRoutedPane(
                routed,
                projection: fresh,
                model: targetModel,
                activateZen: activateZen,
                preservingSidebarScope: preservingSidebarScope
            )
        } failure: {
            guard openRouteToken == token else { return }
            targetModel.reportRouteFailure(
                "Couldn't focus this pane in Herdr. Bessie returned to the current focused pane."
            )
            reconcileFailedPaneRoute(connectionID: routed.connectionID, model: targetModel)
        }
    }

    private func reconcileFailedPaneRoute(connectionID: String, model targetModel: ConnectionViewModel) {
        guard let current = targetModel.projection else {
            selectedTopologyConnectionID = connectionID
            selectedWorkspaceID = nil
            selectedPaneID = nil
            destination = .herd
            if zenState.isActive { zenState.exit() }
            return
        }
        let fallback = current.focusFallback(preferredWorkspaceID: current.focusedWorkspace?.id)
        selectedTopologyConnectionID = connectionID
        selectedWorkspaceID = fallback.workspaceID
        selectedPaneID = fallback.paneID
        destination = fallback.workspaceID == nil ? .herd : .workspace
        if zenState.isActive {
            if let paneID = fallback.paneID { zenState.select(paneID: paneID) }
            else { zenState.exit() }
        }
    }

    private func presentRoutedPane(
        _ routed: RoutedPaneTarget,
        projection fresh: HerdrSessionProjection,
        model targetModel: ConnectionViewModel,
        activateZen: Bool,
        preservingSidebarScope: WorkspaceScope?
    ) {
        guard fresh.panes.contains(where: {
            $0.id == routed.paneID && $0.workspaceID == routed.workspaceID && $0.tabID == routed.tabID
        }) else {
            targetModel.reportRouteFailure(
                "Couldn't open this pane because its Herdr location is no longer current. Refresh The herd and try again."
            )
            reconcileFailedPaneRoute(connectionID: routed.connectionID, model: targetModel)
            return
        }
        selectedTopologyConnectionID = routed.connectionID
        selectedWorkspaceID = routed.workspaceID
        selectedPaneID = routed.paneID
        if let preservingSidebarScope {
            workspaceScope = preservingSidebarScope
        }
        destination = .workspace
        if activateZen {
            zenState.enter(
                paneID: routed.paneID,
                railCollapsed: settings.preferences.railCollapsed
            )
            settings.preferences.railCollapsed = true
        } else if zenState.isActive {
            zenState.select(paneID: routed.paneID)
        }
        if let endpoint = targetModel.terminalEndpoint {
            let presented = fresh.layouts[routed.tabID]?.root.paneIDs ?? [routed.paneID]
            terminalRegistry.reconcile(
                presentedPaneIDs: presented,
                availablePaneIDs: Set(fresh.panes.map(\.id)),
                prewarmPaneIDs: fresh.panes.filter { $0.workspaceID == routed.workspaceID }.map(\.id),
                endpoint: endpoint
            )
        }
        focusTerminal(paneID: routed.paneID)
    }

    private func inspectRoutedPane(_ card: HerdCardModel) {
        let routed = card.paneTarget
        guard let targetModel = fleet.activate(connectionID: routed.connectionID) else { return }
        let target = PaneOpenTarget(
            workspaceID: routed.workspaceID,
            tabID: routed.tabID,
            paneID: routed.paneID
        )
        targetModel.openPane(target) { _ in
            guard fleet.activeConnectionID == routed.connectionID else { return }
            selectedTopologyConnectionID = routed.connectionID
            selectedWorkspaceID = routed.workspaceID
            selectedPaneID = routed.paneID
            destination = .agent
        } failure: {
            destination = .herd
        }
    }

    private func openProjectHandoff(_ handoff: ProjectWorkspaceHandoff) {
        guard let targetModel = fleet.activate(connectionID: handoff.connection.definition.id) else {
            fleet.reportRouteFailure("The Project's target herd is no longer configured.")
            return
        }
        targetModel.openProjectHandoff(handoff) { fresh in
            guard fleet.activeConnectionID == handoff.connection.definition.id else { return }
            selectedTopologyConnectionID = handoff.connection.definition.id
            selectedWorkspaceID = handoff.workspaceID
            selectedPaneID = handoff.paneID
            destination = .workspace
            if let paneID = handoff.paneID,
               let tabID = handoff.tabID,
               let endpoint = targetModel.terminalEndpoint {
                let presented = fresh.layouts[tabID]?.root.paneIDs ?? [paneID]
                terminalRegistry.reconcile(
                    presentedPaneIDs: presented,
                    availablePaneIDs: Set(fresh.panes.map(\.id)),
                    prewarmPaneIDs: fresh.panes.filter { $0.workspaceID == handoff.workspaceID }.map(\.id),
                    endpoint: endpoint
                )
                focusTerminal(paneID: paneID)
            }
        }
    }

    private func handleShortcut(_ command: BessieShortcutCommand) {
        if showCommandPalette,
           !isDispatchingPaletteCommand,
           command != .showCommandPalette {
            return
        }
        if model.actionInFlight {
            switch command {
            case .showCommandPalette, .showHerd, .showSettings, .projectsPicker,
                 .workspacePicker, .openNextNeedsYou, .toggleSidebar, .toggleZen, .exitZen:
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
            if showCommandPalette { commandPalette.dismiss() } else { openCommandPalette() }
        case .showHerd:
            destination = .herd
        case .showSettings:
            destination = .settings
        case .newProject:
            destination = .projects
            projects.beginCreate()
        case .projectsPicker:
            destination = ProductDestination.navigationTarget(for: command) ?? destination
        case .saveCurrentWorkspaceAsProject:
            captureCurrentWorkspaceAsProject()
        case .newWorkspace:
            shortcutEditor = .createWorkspace
        case .renameWorkspace:
            if let workspace { shortcutEditor = .renameWorkspace(id: workspace.id, value: workspace.label) }
        case .closeWorkspace:
            if let workspace { requestClose(.workspace(workspace.id)) }
        case .workspacePicker:
            selectedTopologyConnectionID = model.activeConnection.id
            selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
            selectedPaneID = projection.focusedPane?.id
            destination = .workspace
        case .openNextNeedsYou:
            if zenState.isActive,
               let target = BessieZenAgentRouter.nextNeedsYou(
                   from: currentZenTarget,
                   agents: fleet.agents,
                   connectedConnectionIDs: fleet.connectedConnectionIDs,
                   scope: fleet.herdScope
               ) {
                openRoutedPane(target)
            } else if let card = needsYouCards.first { openRoutedPane(card.paneTarget) }
            else { destination = .herd }
        case .newTab:
            if let workspace { requestTabName(connectionID: model.activeConnection.id, workspaceID: workspace.id) }
        case .renameTab:
            if let tab { shortcutEditor = .renameTab(id: tab.id, value: tab.label) }
        case .previousTab:
            focusTab(offset: -1, tabs: tabs, current: tab)
        case .nextTab:
            focusTab(offset: 1, tabs: tabs, current: tab)
        case .previousPane:
            focusPane(offset: -1, paneIDs: paneIDs, current: paneID)
        case .nextPane:
            focusPane(offset: 1, paneIDs: paneIDs, current: paneID)
        case .previousRailPane:
            openRailPane(offset: -1)
        case .nextRailPane:
            openRailPane(offset: 1)
        case .switchTab(let index):
            guard tabs.indices.contains(index - 1) else { return }
            focusTab(tabs[index - 1])
        case .closeTab:
            if let tab { requestClose(.tab(tab.id)) }
        case .renamePane:
            if let paneID, let pane = projection.panes.first(where: { $0.id == paneID }) {
                shortcutEditor = .renamePane(id: paneID, value: pane.label ?? "")
            }
        case .focusPane(let direction):
            guard let paneID, let tab, let layout = projection.layouts[tab.id],
                  let target = BessiePaneNavigation.target(from: paneID, direction: direction, in: layout.root)
            else { return }
            selectedPaneID = target
            terminalRegistry.recordSwitchRequested(paneID: target)
            terminalRegistry.focusWhenPresented(paneID: target)
            model.navigate([.paneFocus(id: target)])
        case .swapPane(let direction):
            if let paneID { model.perform(.paneSwap(id: paneID, direction: direction)) }

        case .splitPane(let direction):
            if let paneID { requestPaneName(paneID, direction: direction) }
        case .closePane:
            if let paneID { requestClose(.pane(paneID)) }
        case .zoomPane:
            if let paneID { model.perform(.paneZoom(id: paneID, mode: .toggle)) }
        case .resizePane(let direction):
            if let paneID { model.perform(.paneResize(id: paneID, direction: direction, amount: 0.05)) }
        case .toggleSidebar:
            if zenState.isActive {
                exitZen(expandRail: true)
            } else {
                settings.preferences.railCollapsed.toggle()
            }
        case .toggleZen:
            if zenState.isActive {
                exitZen()
            } else if let paneID {
                selectedPaneID = paneID
                selectedTopologyConnectionID = model.activeConnection.id
                if let pane = projection.panes.first(where: { $0.id == paneID }) {
                    selectedWorkspaceID = pane.workspaceID
                }
                destination = .workspace
                zenState.enter(paneID: paneID, railCollapsed: settings.preferences.railCollapsed)
                settings.preferences.railCollapsed = true
                BessieDiagnosticLog.append("Zen entered pane=\(paneID) effect=presentation_only")
            }
        case .exitZen:
            exitZen()
        case .previousAgent:
            openZenAgent(direction: .previous)
        case .nextAgent:
            openZenAgent(direction: .next)
        }
    }

    private var currentZenTarget: RoutedPaneTarget? {
        guard let paneID = zenPaneID,
              let pane = projection.panes.first(where: { $0.id == paneID })
        else { return nil }
        return RoutedPaneTarget(
            connectionID: model.activeConnection.id,
            workspaceID: pane.workspaceID,
            tabID: pane.tabID,
            paneID: pane.id
        )
    }

    private func openZenAgent(direction: BessieZenAgentDirection) {
        guard let target = BessieZenAgentRouter.target(
            direction: direction,
            from: currentZenTarget,
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope
        ) else { return }
        openRoutedPane(target)
    }

    private func exitZen(expandRail: Bool = false) {
            guard zenState.isActive else { return }
            let paneID = zenState.selectedPaneID
            if let paneID {
                selectedPaneID = paneID
                if let pane = projection.panes.first(where: { $0.id == paneID }) {
                    selectedWorkspaceID = pane.workspaceID
                }
            }
            destination = .workspace
            settings.preferences.railCollapsed = zenState.exit(expandRail: expandRail)
            BessieDiagnosticLog.append("Zen exited pane=\(paneID ?? "none") effect=presentation_only")
            // Re-focus after the workspace shell has reattached the terminal host.
            if let paneID {
                DispatchQueue.main.async {
                    self.focusTerminal(paneID: paneID)
                }
            }
        }

    private func focusTerminal(paneID: String) {
        guard terminalRegistry.controllers[paneID] != nil else { return }
        terminalRegistry.recordSwitchRequested(paneID: paneID)
        // Already on-screen panes only need a light paint; park/reattach uses full refresh
        // when the surface attaches (terminalWasPresented).
        let refresh: PaneTerminalController.SurfaceRefresh =
            terminalRegistry.controllers[paneID]?.isSurfacePresented == true ? .display : .full
        terminalRegistry.focusWhenPresented(paneID: paneID, refresh: refresh)
        BessieDiagnosticLog.append("Terminal focus requested pane=\(paneID)")
    }

    private func focusTab(offset: Int, tabs: [TabProjection], current: TabProjection?) {
        guard !tabs.isEmpty else { return }
        let index = current.flatMap { item in tabs.firstIndex { $0.id == item.id } } ?? 0
        focusTab(tabs[(index + offset + tabs.count) % tabs.count])
    }

    private func focusTab(_ target: TabProjection) {
        let paneID = projection.layouts[target.id]?.focusedPaneID
            ?? projection.panes.first(where: { $0.tabID == target.id })?.id
        selectedPaneID = paneID
        if let paneID {
            terminalRegistry.recordSwitchRequested(paneID: paneID)
            terminalRegistry.focusWhenPresented(paneID: paneID)
        }
        model.navigate([.tabFocus(id: target.id)]) { fresh in
            selectedPaneID = fresh.focusedPane?.id ?? paneID
            if let selectedPaneID {
                terminalRegistry.focusWhenPresented(paneID: selectedPaneID, refresh: .full)
            }
        } failure: {
            selectedPaneID = projection.focusedPane?.id
        }
    }

    private func focusPane(offset: Int, paneIDs: [String], current: String?) {
        guard !paneIDs.isEmpty else { return }
        let index = current.flatMap { paneIDs.firstIndex(of: $0) } ?? 0
        let target = paneIDs[(index + offset + paneIDs.count) % paneIDs.count]
        selectedPaneID = target
        terminalRegistry.recordSwitchRequested(paneID: target)
        terminalRegistry.focusWhenPresented(paneID: target)
        model.navigate([.paneFocus(id: target)])
    }

    private func openRailPane(offset: Int) {
        let rows = herdRailProjection.rows
        guard rows.count > 1 else {
            if let row = rows.first { openRoutedPane(row.target) }
            return
        }
        let current = HerdPaneIdentity(
            connectionID: selectedTopologyConnectionID ?? model.activeConnection.id,
            paneID: selectedPaneID ?? projection.focusedPane?.id ?? ""
        )
        let index = rows.firstIndex { $0.id == current }
        let start = index ?? (offset > 0 ? -1 : 0)
        let target = rows[(start + offset + rows.count) % rows.count].target
        openRoutedPane(target)
    }

    private func routePendingNotification() {
        guard let pending = notifications.pendingRoute else { return }
        guard notificationRouteInFlight == nil else { return }
        let target = pending.target
        if target.connectionID != model.activeConnection.id {
            guard fleet.activate(connectionID: target.connectionID) != nil else {
                notifications.consumePendingRoute(pending)
                model.reportRouteFailure(
                    "Couldn't open the notification target because its Herdr connection is unavailable. Reconnect it, then find the agent in The herd."
                )
                destination = .herd
                return
            }
            return
        }
        guard let target = BessieNotificationRoute.resolve(
            pending: target,
            connectionID: model.activeConnection.id,
            projection: projection
        ) else {
            notifications.consumePendingRoute(pending)
            model.reportRouteFailure(
                "Couldn't open the notification target because its workspace, tab, or pane is no longer current. The herd has been refreshed."
            )
            destination = .herd
            return
        }
        notificationRouteInFlight = pending.id
        model.openPane(target) { _ in
            notificationRouteInFlight = nil
            guard notifications.pendingRoute?.id == pending.id else { routePendingNotification(); return }
            notifications.consumePendingRoute(pending)
            selectedTopologyConnectionID = model.activeConnection.id
            selectedWorkspaceID = target.workspaceID
            selectedPaneID = target.paneID
            destination = .workspace
        } failure: {
            notificationRouteInFlight = nil
            guard notifications.pendingRoute?.id == pending.id else { routePendingNotification(); return }
            notifications.consumePendingRoute(pending)
            model.reportRouteFailure(
                "Couldn't open the notification target. The herd has been refreshed; choose the agent's current pane there."
            )
            destination = .herd
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
            placement: .split(
                targetPaneID: targetPaneID,
                direction: .down,
                cwd: environment["BESSIE_PROCESS_CWD"],
                name: environment["BESSIE_PROCESS_PANE_NAME"] ?? "Bessie automation"
            ),
            process: process
        ) { result in
            selectedPaneID = result.paneID
            BessieDiagnosticLog.append(
                "Process launch pane=\(result.paneID) kind=\(agentKind?.isEmpty == false ? agentKind! : "shell") agent_started=\(result.agentStarted) shell_preserved=\(result.agentError != nil)"
            )
        }
    }

    private func runPerformanceSwitchAutomationIfRequested() {
        guard ProcessInfo.processInfo.environment["BESSIE_PANE_SWITCH_PERFORMANCE_PROBE"] == "1",
              !performanceSwitchAutomationStarted
        else { return }
        let byTab = Dictionary(grouping: projection.panes, by: \.tabID)
        let targets = byTab.keys.sorted().prefix(2).compactMap { tabID in
            byTab[tabID]?.sorted { $0.id < $1.id }.first
        }
        guard targets.count == 2 else { return }
        performanceSwitchAutomationStarted = true
        let initialIndex = targets[0].id == projection.focusedPane?.id ? 1 : 0
        runPerformanceSwitchTransition(targets: targets, index: initialIndex, remaining: 20)
    }

    private func runThemeCaptureAutomationIfRequested() {
        guard let outputDirectory = ProcessInfo.processInfo.environment["BESSIE_THEME_LIVE_CAPTURE_DIR"],
              !outputDirectory.isEmpty,
              !themeCaptureAutomationStarted,
              projection.panes.count >= 2
        else { return }
        themeCaptureAutomationStarted = true
        selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
        selectedPaneID = projection.focusedPane?.id
        destination = .workspace
        captureThemeWhenReady(
            outputDirectory: outputDirectory,
            themes: [.dark, .light, .catppuccinLatte, .catppuccinFrappe, .catppuccinMacchiato, .catppuccinMocha],
            identities: terminalRegistry.controllers.mapValues(ObjectIdentifier.init),
            remainingReadinessAttempts: 120
        )
    }

    private func captureThemeWhenReady(
        outputDirectory: String,
        themes: [BessieThemeID],
        identities: [String: ObjectIdentifier],
        remainingReadinessAttempts: Int
    ) {
        let paneControllers = projection.panes.compactMap { terminalRegistry.controllers[$0.id] }
        let ready = paneControllers.count >= 2 && paneControllers.allSatisfy { $0.hasReadyFrame }
        guard ready else {
            guard remainingReadinessAttempts > 0 else {
                BessieDiagnosticLog.append("Theme live capture failed stage=terminal_readiness")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                captureThemeWhenReady(
                    outputDirectory: outputDirectory,
                    themes: themes,
                    identities: identities,
                    remainingReadinessAttempts: remainingReadinessAttempts - 1
                )
            }
            return
        }
        captureNextTheme(outputDirectory: outputDirectory, themes: themes, identities: identities)
    }

    private func captureNextTheme(
        outputDirectory: String,
        themes: [BessieThemeID],
        identities: [String: ObjectIdentifier]
    ) {
        guard let themeID = themes.first else {
            BessieDiagnosticLog.append("Theme live capture complete themes=6 controller_identity=stable")
            return
        }
        guard themeCoordinator.requestSelection(themeID) else {
            BessieDiagnosticLog.append("Theme live capture failed stage=selection theme=\(themeID.rawValue)")
            return
        }
        let expected = BessieThemeRegistry.definitions[themeID]!.resolvedTerminalTheme
        guard terminalRegistry.controllers.allSatisfy({ paneID, controller in
            identities[paneID] == ObjectIdentifier(controller)
                && controller.ghosttyController.theme == expected.theme
                && controller.ghosttyController.effectiveColorScheme == expected.scheme
                && controller.themeConfigurationError == nil
        }) else {
            BessieDiagnosticLog.append("Theme live capture failed stage=controller_consistency theme=\(themeID.rawValue)")
            return
        }
        let filename = "Bessie-theme-\(themeID.captureName)-live.png"
        let path = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename).path
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            BessieWindowSnapshot.capture(path: path)
            captureNextTheme(
                outputDirectory: outputDirectory,
                themes: Array(themes.dropFirst()),
                identities: identities
            )
        }
    }

    private func runPerformanceSwitchTransition(
        targets: [PaneProjection],
        index: Int,
        remaining: Int
    ) {
        guard remaining > 0 else {
            try? BessiePerformance.recorder.flushEvidence()
            BessieDiagnosticLog.append("Performance pane switch probe complete transitions=20 tabs=2")
            return
        }
        let target = targets[index % targets.count]
        selectedWorkspaceID = target.workspaceID
        selectedPaneID = target.id
        destination = .workspace
        terminalRegistry.recordSwitchRequested(paneID: target.id)
        terminalRegistry.focusWhenPresented(paneID: target.id)
        model.navigate([.tabFocus(id: target.tabID), .paneFocus(id: target.id)]) { _ in
            terminalRegistry.focusWhenPresented(paneID: target.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                runPerformanceSwitchTransition(
                    targets: targets,
                    index: index + 1,
                    remaining: remaining - 1
                )
            }
        } failure: {
            BessieDiagnosticLog.append("Performance pane switch probe failed stage=navigation")
        }
    }

    private func prepareShell() {
        destination = ProductDestination.initial(flags: featureFlags)
        fleet.setScope(.all)
        projects.load()
        if commandPaletteMRU.ids.isEmpty {
            commandPaletteMRU = CommandPaletteMRU(ids: fleet.connectionDefinitions.compactMap { connection in
                guard fleet.connectedConnectionIDs.contains(connection.id),
                      let workspaceID = settings.lastWorkspaceID(for: connection.id)
                else { return nil }
                return CommandPaletteEntityID(
                    kind: .workspace,
                    components: [connection.id, workspaceID]
                )
            })
        }
        commandPalette.configure(
            onDispatch: dispatchPaletteRoute,
            onSuccessfulDispatch: { id in
                commandPaletteMRU.record(id)
            },
            onDismiss: closeCommandPalette
        )
        shortcuts.start(isZenActive: { zenState.isActive }) { command in handleShortcut(command) }
        let environment = ProcessInfo.processInfo.environment
        if environment["BESSIE_COMMAND_PALETTE_PREVIEW"] != nil {
            commandPalettePreviewPending = true
            awaitCommandPalettePreviewWindow()
        }
        refreshCommandPaletteAvailability()
        if let preview = environment["BESSIE_DESIGN_PREVIEW"]?.lowercased() {
            selectedWorkspaceID = projection.focusedWorkspace?.id ?? projection.workspaces.first?.id
            selectedPaneID = projection.focusedPane?.id
            if preview == "project-capture" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    projects.beginCaptureCurrentWorkspace()
                }
            } else if preview == "project-launch-review" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if let projectID = projects.projects.first(where: {
                        $0.project.tabs.flatMap(\.panes).contains(where: { $0.command != nil })
                    })?.project.id {
                        projects.requestOpen(projectID)
                    }
                }
            }
        } else {
            restoreActiveSelection()
        }
        selectedTopologyConnectionID = model.activeConnection.id
        consumeNavigationRequest(navigationRequest)
        if environment["BESSIE_ZEN_AUTOMATION"] == "1",
           let paneID = selectedPaneID ?? projection.focusedPane?.id {
            selectedPaneID = paneID
            destination = .workspace
            zenState.enter(
                paneID: paneID,
                railCollapsed: settings.preferences.railCollapsed
            )
            settings.preferences.railCollapsed = true
            BessieDiagnosticLog.append("Zen automation entered pane=\(paneID)")
        } else if environment["BESSIE_TERMINAL_LIVE_AUTOMATION"] == "1",
                  let paneID = projection.focusedPane?.id {
            selectedPaneID = paneID
            destination = .workspace
        }
        routePendingNotification()
    }

    private func activeConnectionChanged() {
        guard BessieActiveConnectionSelection.shouldRestore(
            selectedConnectionID: selectedTopologyConnectionID,
            activeConnectionID: model.activeConnection.id
        ) else { return }
        restoreActiveSelection()
    }

    private func restoreActiveSelection() {
        selectedPaneID = nil
        if settings.preferences.startupBehavior == .lastWorkspace,
           let last = settings.lastWorkspaceID(for: model.activeConnection.id),
           projection.workspaces.contains(where: { $0.id == last }) {
            selectedWorkspaceID = last
            destination = .workspace
        } else {
            selectedWorkspaceID = nil
            destination = .herd
        }
        selectedTopologyConnectionID = model.activeConnection.id
        routePendingNotification()
    }

    private var scopedTargetPane: ScopedPaneItem? {
        let panes = selectedTopologyConnectionID.map { scopedCurrentPanes(connectionID: $0) } ?? []
        if let selectedPaneID, let selected = panes.first(where: { $0.pane.id == selectedPaneID }) {
            return selected
        }
        return panes.first(where: { $0.pane.focused }) ?? panes.first
    }

    private func scopedCurrentPanes(connectionID: String) -> [ScopedPaneItem] {
        guard let workspaceID = selectedWorkspaceID else { return [] }
        let tabs = topology.tabs.filter {
            $0.id.connectionID == connectionID && $0.tab.workspaceID == workspaceID
        }
        let selectedTabID = selectedPaneID.flatMap { paneID in
            topology.panes.first {
                $0.id.connectionID == connectionID
                    && $0.pane.id == paneID
                    && $0.pane.workspaceID == workspaceID
            }?.pane.tabID
        }
        guard let tabID = selectedTabID
                ?? tabs.first(where: { $0.tab.focused })?.tab.id
                ?? tabs.first?.tab.id
        else { return [] }
        return topology.panes.filter { $0.id.connectionID == connectionID && $0.pane.tabID == tabID }
    }

    private func workspaceLabel(_ item: ScopedWorkspaceItem) -> String {
        guard fleet.herdScope == .all else { return item.summary.label }
        let connection = item.connection.kind == .local
            ? "Local"
            : ConnectionDisplayLabel(connection: item.connection).short
        return "\(item.summary.label) · \(connection)"
    }

    private func openWorkspace(_ item: ScopedWorkspaceItem) {
        guard let targetModel = fleet.activate(connectionID: item.id.connectionID) else { return }
        if zenState.isActive { exitZen() }
        workspaceScope = nil
        let operation = UUID()
        topologySelectionInFlight = operation
        selectedTopologyConnectionID = item.id.connectionID
        selectedWorkspaceID = item.id.workspaceID
        selectedPaneID = preferredPaneID(
            connectionID: item.id.connectionID,
            workspaceID: item.id.workspaceID
        )
        destination = .workspace
        if let selectedPaneID {
            terminalRegistry.recordSwitchRequested(paneID: selectedPaneID)
        }
        targetModel.navigate([.workspaceFocus(id: item.id.workspaceID)]) { fresh in
            guard topologySelectionInFlight == operation,
                  fleet.activeConnectionID == item.id.connectionID
            else { return }
            guard let pane = fresh.focusedPane else { return }
            selectedPaneID = pane.id
            if let endpoint = targetModel.terminalEndpoint {
                let presented = fresh.layouts[pane.tabID]?.root.paneIDs ?? [pane.id]
                terminalRegistry.reconcile(
                    presentedPaneIDs: presented,
                    availablePaneIDs: Set(fresh.panes.map(\.id)),
                    prewarmPaneIDs: fresh.panes.filter { $0.workspaceID == item.id.workspaceID }.map(\.id),
                    endpoint: endpoint
                )
            }
            focusTerminal(paneID: pane.id)
        } failure: {
            guard topologySelectionInFlight == operation else { return }
            reconcileFailedPaneRoute(connectionID: item.id.connectionID, model: targetModel)
        }
    }

    private func activateHierarchyHerd(_ row: HerdPickerRow) {
        guard case .connection(let connectionID) = row.scope else { return }
        guard row.isFresh,
              fleet.activate(connectionID: connectionID) != nil
        else {
            if row.canRetry { fleet.retry(connectionID: connectionID) }
            else { openConnectionSettings() }
            return
        }
        fleet.setScope(.all)
        let rememberedID = settings.lastWorkspaceID(for: connectionID)
        let workspaces = freshHierarchyTopology.workspaces.filter { $0.id.connectionID == connectionID }
        let target = rememberedID.flatMap { remembered in
            workspaces.first { $0.id.workspaceID == remembered }
        } ?? workspaces.first(where: { item in
            freshHierarchyTopology.connections.first(where: { $0.connection.id == connectionID })?
                .projection.focusedWorkspace?.id == item.id.workspaceID
        }) ?? workspaces.first
        if let target {
            openWorkspace(target)
        } else {
            selectedTopologyConnectionID = connectionID
            selectedWorkspaceID = nil
            selectedPaneID = nil
            destination = .workspace
        }
    }

    private func showGlobalHierarchy(_ section: WorkspaceHierarchySection) {
        let connectionID = model.activeConnection.id
        let selectedActiveWorkspaceID = selectedTopologyConnectionID == nil
            || selectedTopologyConnectionID == connectionID
            ? selectedWorkspaceID
            : nil
        let workspaceID = selectedActiveWorkspaceID
            ?? projection.focusedWorkspace?.id
            ?? projection.workspaces.first?.id
        guard section == .herd || workspaceID != nil else { return }
        let scope = WorkspaceScopeReducer.selectingAll(
            section,
            connectionID: connectionID,
            workspaceID: workspaceID ?? ""
        )
        workspaceScope = scope
        reconcileWorkspaceScopeSelection(scope)
    }

    private func reconcileWorkspaceScopeSelection(_ scope: WorkspaceScope) {
        let filtered = WorkspaceScopeReducer.filtered(baseHerdRailProjection, scope: scope)
        let retained = selectedPaneID.map {
            HerdPaneIdentity(
                connectionID: selectedTopologyConnectionID ?? model.activeConnection.id,
                paneID: $0
            )
        }
        guard let target = WorkspaceScopeReducer.selection(
            in: filtered,
            retaining: retained,
            focused: focusedHerdPanes
        ) else {
            selectedPaneID = nil
            return
        }
        selectedTopologyConnectionID = target.connectionID
        selectedWorkspaceID = target.workspaceID
        selectedPaneID = target.paneID
    }

    private func openConnectionSettings() {
        settings.requestAddConnection()
        destination = .settings
    }

    private func captureCurrentWorkspaceAsProject() {
        guard WorkspaceProjectCaptureGate.isSettled(
                actionInFlight: model.actionInFlight,
                navigationInFlight: model.navigationInFlight
              ),
              selectedTopologyConnectionID == model.activeConnection.id,
              selectedWorkspaceID == projection.focusedWorkspace?.id
        else {
            projects.reportCaptureUnavailable("Wait for Herdr to focus this workspace before capturing it.")
            destination = .projects
            return
        }
        guard projects.beginCaptureCurrentWorkspace() else { return }
        destination = .projects
    }

    private func focusHierarchyTab(_ tabID: String) {
        guard let target = projection.tabs.first(where: { $0.id == tabID }) else { return }
        workspaceScope = nil
        destination = .workspace
        focusTab(target)
    }

    private func createHierarchyTab() {
        guard let workspaceID = hierarchyPresentation.workspaceID else { return }
        requestTabName(connectionID: model.activeConnection.id, workspaceID: workspaceID)
    }

    private func preferredPaneID(connectionID: String, workspaceID: String) -> String? {
        let tabs = topology.tabs.filter {
            $0.id.connectionID == connectionID && $0.tab.workspaceID == workspaceID
        }
        guard let tabID = tabs.first(where: { $0.tab.focused })?.tab.id ?? tabs.first?.tab.id else { return nil }
        let panes = topology.panes.filter {
            $0.id.connectionID == connectionID && $0.pane.tabID == tabID
        }
        return panes.first(where: { $0.pane.focused })?.pane.id ?? panes.first?.pane.id
    }

    private func renameWorkspace(_ item: ScopedWorkspaceItem) {
        guard fleet.activate(connectionID: item.id.connectionID) != nil else { return }
        selectedTopologyConnectionID = item.id.connectionID
        shortcutEditor = .renameWorkspace(id: item.id.workspaceID, value: item.summary.label)
    }

    private func renameTopologyPane(_ item: ScopedPaneItem) {
        guard fleet.activate(connectionID: item.id.connectionID) != nil else { return }
        selectedTopologyConnectionID = item.id.connectionID
        shortcutEditor = .renamePane(id: item.pane.id, value: item.pane.label ?? "")
    }

    private func scopedPane(for target: RoutedPaneTarget) -> ScopedPaneItem? {
        topology.panes.first {
            $0.id.connectionID == target.connectionID
                && $0.pane.id == target.paneID
                && $0.pane.workspaceID == target.workspaceID
                && $0.pane.tabID == target.tabID
        }
    }

    private func topologyPaneMoveChoices(_ item: ScopedPaneItem) -> PaneMoveChoices? {
        topology.connections.first { $0.connection.id == item.id.connectionID }.flatMap {
            PaneMoveChoices(projection: $0.projection, paneID: item.pane.id)
        }
    }

    private func topologyPaneController(_ item: ScopedPaneItem?) -> PaneTerminalController? {
        guard let item, terminalEndpoint.connectionID == item.id.connectionID else { return nil }
        return terminalRegistry.controllers[item.pane.id]
    }

    private func closeTopologyWorkspace(_ item: ScopedWorkspaceItem) {
        topologyWorkspaceClose = nil
        guard let targetModel = fleet.activate(connectionID: item.id.connectionID) else { return }
        targetModel.perform(.workspaceClose(id: item.id.workspaceID), confirmDestructive: true) { fresh in
            applyCloseReconciliation(
                BessieCloseReconciliation(
                    connectionID: item.id.connectionID,
                    projection: fresh,
                    preferredWorkspaceID: nil
                )
            )
        }
    }

    private func closeTopologyPane(_ item: ScopedPaneItem) {
        topologyPaneClose = nil
        guard let owner = topology.connections.first(where: { $0.connection.id == item.id.connectionID }),
              let targetModel = fleet.activate(connectionID: item.id.connectionID)
        else { return }
        workspaceScope = nil
        let operation = UUID()
        topologySelectionInFlight = operation
        let close = PendingClose.pane(item.pane.id)
        targetModel.perform(
            close.resolvedAction(in: owner.projection),
            confirmDestructive: close.requiresIntentConfirmation(in: owner.projection)
        ) { fresh in
            guard topologySelectionInFlight == operation,
                  fleet.activeConnectionID == item.id.connectionID
            else { return }
            applyCloseReconciliation(
                BessieCloseReconciliation(
                    connectionID: item.id.connectionID,
                    projection: fresh,
                    preferredWorkspaceID: item.pane.workspaceID
                )
            )
        }
    }

    private func performPaneAction(_ item: ScopedPaneItem, _ action: HerdrAction) {
        guard let targetModel = fleet.activate(connectionID: item.id.connectionID) else { return }
        let operation = UUID()
        topologySelectionInFlight = operation
        targetModel.perform(action) { fresh in
            guard topologySelectionInFlight == operation,
                  fleet.activeConnectionID == item.id.connectionID
            else { return }
            let fallback = fresh.focusFallback(preferredWorkspaceID: item.pane.workspaceID)
            selectedTopologyConnectionID = item.id.connectionID
            selectedWorkspaceID = fallback.workspaceID
            selectedPaneID = fallback.paneID
            destination = fallback.workspaceID == nil ? .herd : .workspace
        }
    }

    private func enterZen(paneID: String) {
        if zenState.isActive, zenPaneID == paneID {
            exitZen()
            return
        }
        guard let pane = projection.panes.first(where: { $0.id == paneID }) else { return }
        selectedTopologyConnectionID = model.activeConnection.id
        selectedWorkspaceID = pane.workspaceID
        selectedPaneID = pane.id
        destination = .workspace
        zenState.enter(paneID: pane.id, railCollapsed: settings.preferences.railCollapsed)
        settings.preferences.railCollapsed = true
        BessieDiagnosticLog.append("Zen entered pane=\(pane.id) effect=presentation_only")
    }

    private func performConfirmedClose(_ close: PendingClose) {
        guard shortcutCloseConnectionID == model.activeConnection.id else {
            shortcutClose = nil
            shortcutCloseConnectionID = nil
            return
        }
        let preferredWorkspaceID = close.parentWorkspaceID(in: projection)
        model.perform(
            close.resolvedAction(in: projection),
            confirmDestructive: close.requiresIntentConfirmation(in: projection)
        ) { fresh in
            applyCloseReconciliation(
                BessieCloseReconciliation(
                    connectionID: model.activeConnection.id,
                    projection: fresh,
                    preferredWorkspaceID: preferredWorkspaceID
                )
            )
        }
    }

    private func cancelShortcutClose() {
        let paneID = selectedPaneID ?? projection.focusedPane?.id
        shortcutClose = nil
        shortcutCloseConnectionID = nil
        if let paneID { terminalRegistry.focusWhenPresented(paneID: paneID) }
    }

    private func requestClose(_ close: PendingClose) {
        shortcutCloseConnectionID = model.activeConnection.id
        shortcutClose = close
    }

    private func applyCloseReconciliation(_ result: BessieCloseReconciliation) {
        selectedTopologyConnectionID = result.connectionID
        selectedWorkspaceID = result.workspaceID
        selectedPaneID = result.paneID
        destination = result.destination
        if result.exitsZen {
            if zenState.isActive { zenState.exit() }
        } else if zenState.isActive {
            if let paneID = result.paneID { zenState.enter(paneID: paneID) }
            else { zenState.exit() }
        }
    }

    private func createWorkspace() {
        let connectionID: String
        switch fleet.herdScope {
        case .all:
            connectionID = selectedTopologyConnectionID ?? model.activeConnection.id
        case .connection(let id):
            connectionID = id
        }
        guard topology.connections.contains(where: { $0.connection.id == connectionID }),
              let targetModel = fleet.activate(connectionID: connectionID)
        else { return }
        let operation = UUID()
        topologySelectionInFlight = operation
        targetModel.perform(TopologyCreation.workspace.action) { fresh in
            guard topologySelectionInFlight == operation,
                  fleet.activeConnectionID == connectionID
            else { return }
            selectedTopologyConnectionID = connectionID
            selectedWorkspaceID = fresh.focusedWorkspace?.id
            selectedPaneID = fresh.focusedPane?.id
            destination = .workspace
        }
    }

    private func requestTabName(connectionID: String, workspaceID: String) {
        namedTopologyRequest = NamedTopologyRequest(
            target: .tab(connectionID: connectionID, workspaceID: workspaceID)
        )
    }

    private func requestPaneName(_ paneID: String, direction: SplitDirection) {
        requestPaneName(connectionID: model.activeConnection.id, paneID: paneID, direction: direction)
    }

    private func requestPaneName(connectionID: String, paneID: String, direction: SplitDirection) {
        namedTopologyRequest = NamedTopologyRequest(
            target: .pane(connectionID: connectionID, targetPaneID: paneID, direction: direction)
        )
    }

    private func requestMoveToNewTabName(_ paneID: String, workspaceID: String) {
        requestMoveToNewTabName(
            connectionID: model.activeConnection.id,
            paneID: paneID,
            workspaceID: workspaceID
        )
    }

    private func requestMoveToNewTabName(connectionID: String, paneID: String, workspaceID: String) {
        namedTopologyRequest = NamedTopologyRequest(
            target: .movedPaneTab(
                connectionID: connectionID,
                paneID: paneID,
                workspaceID: workspaceID
            )
        )
    }

    private func performNamedTopologyRequest(_ request: NamedTopologyRequest, name: String) {
        switch request.target {
        case .tab(let connectionID, let workspaceID):
            createTab(connectionID: connectionID, workspaceID: workspaceID, name: name)
        case .pane(let connectionID, let targetPaneID, let direction):
            createPane(connectionID: connectionID, targetPaneID: targetPaneID, direction: direction, name: name)
        case .movedPaneTab(let connectionID, let paneID, let workspaceID):
            guard let targetModel = fleet.activate(connectionID: connectionID) else { return }
            targetModel.perform(
                .paneMove(
                    id: paneID,
                    destination: .newTab(
                        workspaceID: workspaceID,
                        label: name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ),
                    focus: true
                )
            )
        }
    }

    private func createTab(connectionID: String, workspaceID: String, name: String) {
        guard let targetModel = fleet.activate(connectionID: connectionID) else { return }
        let operation = UUID()
        topologySelectionInFlight = operation
        targetModel.perform(TopologyCreation.tab(workspaceID: workspaceID, name: name).action) { fresh in
            guard topologySelectionInFlight == operation,
                  fleet.activeConnectionID == connectionID
            else { return }
            selectedTopologyConnectionID = connectionID
            selectedWorkspaceID = workspaceID
            selectedPaneID = fresh.focusedPane?.id
            destination = .workspace
            if let selectedPaneID {
                terminalRegistry.recordSwitchRequested(paneID: selectedPaneID)
                terminalRegistry.focusWhenPresented(paneID: selectedPaneID, refresh: .full)
            }
        }
    }

    private func createPane(
        connectionID: String,
        targetPaneID: String,
        direction: SplitDirection,
        name: String
    ) {
        guard let owner = topology.connections.first(where: { $0.connection.id == connectionID }),
              let targetPane = owner.projection.panes.first(where: { $0.id == targetPaneID }),
              let targetModel = fleet.activate(connectionID: connectionID)
        else { return }
        let priorPaneIDs = Set(owner.projection.panes.map(\.id))
        let creation = TopologyCreation.pane(targetPaneID: targetPaneID, direction: direction, name: name)
        let operation = UUID()
        topologySelectionInFlight = operation
        targetModel.perform(creation.action) { fresh in
            guard topologySelectionInFlight == operation,
                  fleet.activeConnectionID == connectionID
            else { return }
            let createdPane = fresh.panes.first { !priorPaneIDs.contains($0.id) }
            selectedTopologyConnectionID = connectionID
            selectedWorkspaceID = targetPane.workspaceID
            selectedPaneID = createdPane?.id ?? fresh.focusedPane?.id
            destination = .workspace
            guard let createdPane,
                  let renameAction = creation.followUpAction(createdPaneID: createdPane.id)
            else { return }
            targetModel.perform(renameAction) { renamed in
                guard topologySelectionInFlight == operation,
                      fleet.activeConnectionID == connectionID
                else { return }
                selectedPaneID = renamed.panes.first(where: { $0.id == createdPane.id })?.id
                    ?? renamed.focusedPane?.id
            }
        }
    }

    private func reconcileSelection(for scope: ConnectionScope) {
        let connectionID: String
        switch scope {
        case .all:
            connectionID = selectedTopologyConnectionID ?? model.activeConnection.id
        case .connection(let id):
            connectionID = id
        }
        let scoped = ScopedTopologyProjection(connections: fleet.topologyConnections, scope: scope)
        guard let connection = scoped.connections.first(where: { $0.connection.id == connectionID })
                ?? scoped.connections.first
        else {
            selectedTopologyConnectionID = connectionID
            // Do not invent a workspace when the authoritative projection is empty.
            if selectedWorkspaceID != nil {
                selectedWorkspaceID = nil
                selectedPaneID = nil
                destination = .herd
                if zenState.isActive { zenState.exit() }
            }
            return
        }
        selectedTopologyConnectionID = connection.connection.id
        // If the open workspace disappeared, fall back to fresh authoritative state.
        guard connection.projection.workspaces.contains(where: { $0.id == selectedWorkspaceID }) else {
            if destination == .workspace || destination == .agent || destination == .files {
                selectedWorkspaceID = connection.projection.focusedWorkspace?.id
                    ?? connection.projection.workspaces.first?.id
                selectedPaneID = connection.projection.focusedPane?.id
                if selectedWorkspaceID == nil {
                    destination = .herd
                    if zenState.isActive { zenState.exit() }
                }
            }
            return
        }
        if let selectedPaneID,
           !connection.projection.panes.contains(where: {
               $0.id == selectedPaneID && $0.workspaceID == selectedWorkspaceID
           }) {
            self.selectedPaneID = connection.projection.panes.first(where: {
                $0.focused && $0.workspaceID == selectedWorkspaceID
            })?.id
        }
    }

    private func consumeNavigationRequest(_ request: ProductNavigationRequest?) {
        guard let request else { return }
        guard request.connectionID == model.activeConnection.id else {
            _ = fleet.activate(connectionID: request.connectionID)
            return
        }
        guard request.target(connectionID: model.activeConnection.id, projection: projection) != nil else {
            navigationRequest = nil
            destination = .herd
            return
        }
        selectedTopologyConnectionID = request.connectionID
        selectedWorkspaceID = request.workspaceID
        selectedPaneID = request.paneID
        destination = .workspace
        navigationRequest = nil
    }
}

struct BessieZenDisconnectedSurface: View {
    let connection: BessieConnectionDefinition
    let presentation: ConnectPresentation
    let retry: () -> Void
    let exit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 18, weight: .medium))
                Text(ConnectionDisplayLabel(connection: connection).short)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Exit Zen", action: exit)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(BessieDesign.strong)
            .padding(.vertical, 16)
            .frame(width: 76)
            .background(BessieDesign.rail)
            .overlay(alignment: .trailing) { Rectangle().fill(BessieDesign.border).frame(width: 1) }

            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 26, weight: .medium))
                Text(presentation.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(presentation.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(BessieDesign.subtle)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                HStack(spacing: 8) {
                    Button("Try again", action: retry)
                        .buttonStyle(BessiePrimaryButtonStyle())
                    Button("Exit Zen", action: exit)
                        .buttonStyle(BessieSecondaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BessieDesign.background)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zen mode connection unavailable")
    }
}

private struct BessieZenSurface: View {
    let paneID: String
    let controller: PaneTerminalController?
    let agentCards: [HerdCardModel]
    let selectedAgentID: String?
    let currentPath: String
    let elsewhereCount: Int
    let terminalFontSize: Double
    var mouseAgent: String? = nil
    var mouseForegroundCWD: String? = nil
    let exit: () -> Void
    let nextNeedsYou: () -> Void
    let openAgent: (RoutedPaneTarget) -> Void
    let focus: () -> Void

    private static let isDesignCapture = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "14"

    private var visibleAgentCards: [HerdCardModel] {
        Self.isDesignCapture ? Self.captureAgentCards : agentCards
    }

    private var visibleCurrentPath: String {
        Self.isDesignCapture ? "bessie / dev / theme" : currentPath
    }

    private var visibleElsewhereCount: Int {
        Self.isDesignCapture ? 1 : elsewhereCount
    }

    private static let captureAgentCards: [HerdCardModel] = {
        let fixtures: [(String, String, AgentSemanticState)] = [
            ("theme", "claude", .blocked),
            ("schema", "codex", .blocked),
            ("motion", "codex", .working),
            ("perf", "grok", .working),
            ("sync", "claude", .done),
            ("snapshots", "amp", .done),
            ("notes", "claude", .idle),
            ("scratch", "codex", .unknown),
        ]
        return fixtures.map { identity, provider, state in
            HerdCardModel(
                id: identity,
                connectionID: "capture",
                connectionLabel: "This Mac",
                connectionDetail: "local",
                identity: identity,
                agentKind: provider,
                state: state,
                location: "bessie / dev / \(identity)",
                activity: nil,
                paneTarget: RoutedPaneTarget(
                    connectionID: "capture",
                    workspaceID: "bessie",
                    tabID: "dev",
                    paneID: identity
                )
            )
        }
    }()

    var body: some View {
        HStack(spacing: BessieZenPresentationContract.gutter) {
            VStack(spacing: 0) {
                BessiePhosphorCow(size: 17)
                    .opacity(0.6)
                    .padding(.top, 13)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(visibleAgentCards) { card in
                            Button { openAgent(card.paneTarget) } label: {
                                HStack(spacing: 5) {
                                    BessieStatusGlyph(state: card.state)
                                    BessieProviderMark(provider: card.agentKind)
                                }
                                .frame(width: 40, height: 28)
                                .background(isSelected(card) ? BessieDesign.selected : BessieSemanticColor.clear)
                                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                                .overlay(alignment: .leading) {
                                    if isSelected(card) {
                                        Rectangle()
                                            .fill(BessieDesign.accent)
                                            .frame(width: 2.5, height: 16)
                                            .offset(x: -6)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Open \(card.identity)")
                            .accessibilityLabel("Open \(card.identity), \(card.state.title), \(card.location)")
                            .accessibilityValue(isSelected(card) ? "Selected" : "Not selected")
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }

                Spacer(minLength: 8)

                Button(action: exit) {
                    BessieIconView(icon: .caretRight, size: 14)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("\(BessieZenControlLabels.expand) (Esc)")
                .accessibilityLabel("\(BessieZenControlLabels.expand), exits Zen, Escape")
                .padding(.vertical, 8)
            }
            .frame(width: BessieZenPresentationContract.awarenessRailWidth)
            .accessibilityElement(children: .contain)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(visibleCurrentPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(BessieDesign.faint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Current path, \(visibleCurrentPath)")

                    Spacer(minLength: 8)

                    if let label = BessieZenPresentationContract.elsewhereLabel(count: visibleElsewhereCount) {
                        Button(action: nextNeedsYou) {
                            HStack(spacing: 6) {
                                AgentStateGlyph(state: .blocked, size: 7)
                                Text(label)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Open next agent that needs you")
                        .accessibilityLabel("\(label), open next agent that needs you")
                    }

                    Text("⌘⇧Z")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(BessieDesign.faint)
                .padding(.horizontal, 18)
                .frame(height: BessieZenPresentationContract.terminalHeaderHeight)
                .opacity(0.5)
                .accessibilityElement(children: .contain)

                Group {
                    if let controller {
                        RecoverableTerminalSurface(
                            controller: controller,
                            fontSize: terminalFontSize,
                            requestFocus: {
                                controller.makeTerminalFirstResponder(refresh: .display)
                            }
                        )
                        .onAppear {
                            controller.updateMouseCapture(agent: mouseAgent, foregroundCWD: mouseForegroundCWD)
                        }
                        .onChange(of: mouseAgent) { _, agent in
                            controller.updateMouseCapture(agent: agent, foregroundCWD: mouseForegroundCWD)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(BessieDesign.code)
                    }
                }
                .accessibilityLabel("Zen terminal, pane \(paneID)")
            }
            .background(BessieDesign.code)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.surfaceRadius))
            .overlay { RoundedRectangle(cornerRadius: BessieDesign.surfaceRadius).stroke(BessieDesign.border, lineWidth: 1) }
            .padding(.trailing, BessieZenPresentationContract.gutter)
            .padding(.bottom, BessieZenPresentationContract.gutter)
        }
        .background(Color.clear)
        .padding(.leading, BessieZenPresentationContract.gutter)
        // The HTML artboard's one-pixel outer window stroke reduces the body
        // layout bounds. Native AppKit draws that stroke outside SwiftUI's
        // content coordinates, so preserve the same inner card geometry here.
        .padding(.horizontal, 1)
        .padding(.bottom, 1)
        .bessieOnboardingWindowTitle(BessieZenPresentationContract.windowTitle)
        .onChange(of: controller?.id) { _, _ in focus() }
    }

    private func isSelected(_ card: HerdCardModel) -> Bool {
        card.id == selectedAgentID
            || (Self.isDesignCapture && card.id == "theme")
    }

}

private struct HerdSurface: View {
    @ObservedObject var fleet: ConnectionFleetViewModel
    let openPane: (RoutedPaneTarget) -> Void
    let inspectPane: (HerdCardModel) -> Void
    let createWorkspace: () -> Void
    let openSettings: () -> Void
    @State private var filter: HerdListFilter = .all
    @Environment(\.bessieDensity) private var density

    private var cards: [HerdCardModel] {
        HerdListBuilder.cards(
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope,
            filter: filter
        )
    }

    private var counts: [HerdListFilter: Int] {
        HerdListBuilder.counts(
            agents: fleet.agents,
            connectedConnectionIDs: fleet.connectedConnectionIDs,
            scope: fleet.herdScope
        )
    }

    private var connectionIssues: [FleetConnectionIssue] {
        fleet.connectionIssues.filter { issue in
            switch fleet.herdScope {
            case .all: true
            case .connection(let id): issue.id == id
            }
        }
    }

    private var scopedConnectionAvailable: Bool {
        switch fleet.herdScope {
        case .all: !fleet.connectedConnectionIDs.isEmpty
        case .connection(let id): fleet.connectedConnectionIDs.contains(id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: "The herd") {
                let count = counts[.all, default: 0]
                if count > 0 {
                    Text("\(count) agent\(count == 1 ? "" : "s")")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(BessieDesign.subtle)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !connectionIssues.isEmpty {
                        connectionIssueRows
                            .padding(.bottom, 14)
                    }

                    if counts[.all, default: 0] > 0 {
                        HStack(alignment: .bottom) {
                            Spacer()
                            herdFilters
                        }
                        .padding(.bottom, 18)
                    }

                    if cards.isEmpty {
                        let noConnections = !scopedConnectionAvailable
                        ProductEmptyState(
                            symbol: "circle.grid.3x3",
                            title: noConnections ? "No connected sessions" : (counts[.all, default: 0] == 0 ? "No agents running" : "No matching agents"),
                            detail: noConnections ? "Open Settings to reconnect. Your Herdr work may still be running." : (counts[.all, default: 0] == 0 ? "Open a workspace and start a process." : "Choose another filter."),
                            actionTitle: noConnections ? "Open Settings" : (counts[.all, default: 0] == 0 ? "Create workspace" : "Show all agents"),
                            action: noConnections ? openSettings : (counts[.all, default: 0] == 0 ? createWorkspace : { filter = .all })
                        )
                        .frame(minHeight: 300)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: density.cardGap), count: 3), alignment: .leading, spacing: density.cardGap) {
                            ForEach(cards) { card in
                                herdCard(card)
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
            ForEach(HerdListFilter.allCases, id: \.self) { item in
                Button { filter = item } label: {
                    HStack(spacing: 5) {
                        Text(item.rawValue)
                        Text("\(counts[item, default: 0])")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(filter == item ? BessieDesign.text : BessieDesign.faint)
                    }
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: filter == item ? .semibold : .regular))
                    .foregroundStyle(filter == item ? BessieDesign.strong : BessieDesign.subtle)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(filter == item ? BessieDesign.selected : BessieSemanticColor.clear)
            }
        }
        .padding(2)
        .background(BessieDesign.inset)
        .overlay { RoundedRectangle(cornerRadius: BessieDesign.controlRadius).stroke(BessieDesign.border, lineWidth: 1) }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }

    private var connectionIssueRows: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(connectionIssues) { issue in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(issue.label)
                        .fontWeight(.semibold)
                    Text(issue.title)
                    Spacer()
                    Text(issue.detail)
                        .foregroundStyle(BessieDesign.faint)
                        .lineLimit(1)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(BessieDesign.subtle)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(BessieDesign.inset)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(BessieDesign.border, lineWidth: 1) }
            }
        }
    }

    private func herdCard(_ card: HerdCardModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AgentStateGlyph(state: herdGlyphState(card.presentationStatus), size: 7)
                    .accessibilityLabel(card.presentationStatus.rawValue)
                Text(card.identity)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BessieDesign.strong)
                    .lineLimit(1)
                Spacer()
                Text(card.presentationStatus.rawValue)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(stateColor(card.presentationStatus))
            }
            .padding(.horizontal, 12)
            .frame(height: density.herdCardHeaderHeight)

            Rectangle().fill(BessieDesign.border).frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text(card.connectionLabel)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(BessieDesign.selected)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .help(card.connectionDetail)
                    Text(card.location)
                        .lineLimit(1)
                }
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                if let activity = card.activity {
                    Text(activity)
                        .font(.system(size: 12))
                        .foregroundStyle(BessieDesign.text)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
                } else {
                    Spacer().frame(minHeight: 48)
                }
            }
            .padding(density.herdCardPadding)

            HStack(spacing: 7) {
                Spacer()
                Button("Open pane") { openPane(card.paneTarget) }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Details") { inspectPane(card) }
                    .buttonStyle(BessieQuietButtonStyle())
            }
            .padding(.horizontal, 10)
            .frame(height: density.herdCardFooterHeight)
            .background(BessieDesign.inset.opacity(0.7))
        }
        .background(BessieMaterialBackground(base: BessieDesign.panel, radius: BessieDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BessieDesign.cardRadius)
                .stroke(card.state == .blocked ? BessieDesign.strong.opacity(0.72) : BessieDesign.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.cardRadius))
    }

    private func stateColor(_ status: HerdPresentationStatus) -> BessieSemanticColor {
        switch status {
        case .needsYou: BessieDesign.strong
        case .working: BessieDesign.running
        case .settled: BessieDesign.done
        case .unknown: BessieDesign.idle
        }
    }

    private func herdGlyphState(_ status: HerdPresentationStatus) -> AgentSemanticState {
        switch status {
        case .needsYou: .blocked
        case .working: .working
        case .settled: .done
        case .unknown: .unknown
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
    let followFilesEnabled: Bool
    let openWorkspace: () -> Void
    @State private var prompt = ""
    @State private var editor: ProductEditor?
    @Environment(\.bessieDensity) private var density
    @State private var workbenchSection: WorkbenchSection = .details
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
                crumbs: [ConnectionDisplayLabel(connection: model.activeConnection).short, workspace?.label, tab?.label].compactMap { $0 },
                title: pane?.agent ?? pane?.label ?? pane?.title ?? "Pane"
            ) {
                if let pane {
                    Button("Rename") { editor = .renamePane(id: pane.id, value: pane.label ?? "") }
                        .buttonStyle(BessieSecondaryButtonStyle())
                    Button("Open workspace", action: openWorkspace)
                        .buttonStyle(BessiePrimaryButtonStyle())
                }
            }

            if followFilesEnabled, model.activeConnection.kind == .ssh, model.remoteFileAccess == nil { RemoteWorkspaceFilesBanner() }

            if let pane {
                HSplitView {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            AgentStateGlyph(state: AgentSemanticState(herdrValue: pane.agentStatus), size: 6)
                            Text(pane.presentationTitle)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            if let controller { PaneControllerStatusLabel(controller: controller) }
                            else { Text("Connecting").font(.system(size: 9, design: .monospaced)).foregroundStyle(BessieDesign.subtle) }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: density.paneHeaderHeight)
                        .background(BessieDesign.panel)
                        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }

                        if let controller {
                            RecoverableTerminalSurface(
                                controller: controller,
                                fontSize: terminalFontSize,
                                requestFocus: {
                                    controller.makeTerminalFirstResponder(refresh: .display)
                                }
                            )
                            .onAppear {
                                controller.updateMouseCapture(agent: pane.agent, foregroundCWD: pane.foregroundCWD)
                            }
                            .onChange(of: pane.agent) { _, agent in
                                controller.updateMouseCapture(agent: agent, foregroundCWD: pane.foregroundCWD)
                            }
                            .onChange(of: pane.foregroundCWD) { _, cwd in
                                controller.updateMouseCapture(agent: pane.agent, foregroundCWD: cwd)
                            }
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
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    agentWorkbench(pane)
                        .frame(minWidth: 260, idealWidth: 420, maxWidth: 720)
                }
                .padding(density.cardGap)
            } else {
                ProductEmptyState(symbol: "terminal", title: "No agent selected", detail: "Choose an agent from The herd.", action: nil)
            }
        }
        .task(id: followContextSignature) {
            if followFilesEnabled, let pane {
                followFiles.configure(
                    connection: model.activeConnection,
                    projection: projection,
                    paneID: pane.id,
                    remoteFileAccess: model.remoteFileAccess
                )
            } else { followFiles.stop() }
        }
        .onAppear { selectedPaneID = pane?.id }
        .onDisappear { followFiles.stop() }
        .sheet(item: $editor) { ProductEditorSheet(editor: $0) { action in model.perform(action); editor = nil } }
    }

    private func agentWorkbench(_ pane: PaneProjection) -> some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Workbench", selection: $workbenchSection) {
                    Text(WorkbenchSection.details.rawValue).tag(WorkbenchSection.details)
                    if followFilesEnabled { Text(WorkbenchSection.changes.rawValue).tag(WorkbenchSection.changes) }
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
                        workbenchRow("NAME", pane.presentationTitle)
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
                if followFilesEnabled { FollowFilesSurface(model: followFiles) }
                else { EmptyView() }
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
        controller.inputRouter.enqueue(.raw(Data(value.utf8)))
        controller.inputRouter.enqueue(.keys(["enter"]))
        prompt = ""
    }
}

private struct GlobalWorkspacesSurface: View {
    let topology: ScopedTopologyProjection
    let open: (ScopedWorkspaceItem) -> Void
    let createWorkspace: () -> Void

    private var rows: [ScopedWorkspaceItem] {
        topology.workspaces.sorted {
            let order = $0.summary.label.localizedCaseInsensitiveCompare($1.summary.label)
            return order == .orderedSame
                ? $0.id.connectionID < $1.id.connectionID
                : order == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: WorkspaceHierarchySection.workspace.allTitle) {
                Button("New workspace", systemImage: "plus", action: createWorkspace)
                    .buttonStyle(ProductPrimaryButton())
            }

            ScrollView {
                Group {
                    if rows.isEmpty {
                        ProductEmptyState(
                            symbol: "square.grid.2x2",
                            title: "No workspaces",
                            detail: "Connect a herd or create a workspace to see it here."
                        ) { createWorkspace() }
                    } else {
                        LazyVStack(spacing: 7) {
                            ForEach(rows) { item in
                                GlobalTopologyRow(
                                    symbol: "square.grid.2x2",
                                    title: item.summary.label,
                                    detail: "\(globalConnectionLabel(item.connection)) · \(BessieSidebarSessionSummary.text(tabCount: item.summary.tabCount, paneCount: item.summary.paneCount))",
                                    action: { open(item) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 34)
                .padding(.bottom, 60)
            }
        }
    }
}

private struct GlobalTabsSurface: View {
    let topology: ScopedTopologyProjection
    let open: (TopologyTabID) -> Void
    let createWorkspace: () -> Void

    private var rows: [ScopedTabItem] {
        topology.tabs.sorted {
            let order = $0.tab.label.localizedCaseInsensitiveCompare($1.tab.label)
            return order == .orderedSame
                ? $0.id.connectionID < $1.id.connectionID
                : order == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BessieTopBar(title: WorkspaceHierarchySection.tab.allTitle) {
                Button("New workspace", systemImage: "plus", action: createWorkspace)
                    .buttonStyle(ProductPrimaryButton())
            }

            ScrollView {
                Group {
                    if rows.isEmpty {
                        ProductEmptyState(
                            symbol: "rectangle.stack",
                            title: "No tabs",
                            detail: "Connect a herd or create a workspace to see its tabs here."
                        ) { createWorkspace() }
                    } else {
                        LazyVStack(spacing: 7) {
                            ForEach(rows) { item in
                                GlobalTopologyRow(
                                    symbol: "rectangle.stack",
                                    title: item.tab.label,
                                    detail: tabDetail(item),
                                    action: { open(item.id) }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 34)
                .padding(.bottom, 60)
            }
        }
    }

    private func tabDetail(_ item: ScopedTabItem) -> String {
        let workspace = topology.workspaces.first {
            $0.id.connectionID == item.id.connectionID
                && $0.id.workspaceID == item.tab.workspaceID
        }
        let connection = topology.connections.first { $0.connection.id == item.id.connectionID }?.connection
        let paneCount = topology.panes.filter {
            $0.id.connectionID == item.id.connectionID && $0.pane.tabID == item.tab.id
        }.count
        let workspaceLabel = workspace?.summary.label ?? item.tab.workspaceID
        let connectionLabel = connection.map(globalConnectionLabel) ?? item.id.connectionID
        return "\(workspaceLabel) · \(connectionLabel) · \(paneCount) \(paneCount == 1 ? "pane" : "panes")"
    }
}

private struct GlobalTopologyRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BessieDesign.subtle)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(BessieDesign.strong)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BessieDesign.subtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BessieDesign.faint)
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
        .accessibilityLabel("Open \(title), \(detail)")
    }
}

private func globalConnectionLabel(_ connection: BessieConnectionDefinition) -> String {
    connection.kind == .local
        ? "local"
        : ConnectionDisplayLabel(connection: connection).short
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
                                                if item.requiresUserActionCount > 0 {
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
                                .contextMenu {
                                    Button("Rename") { editor = .renameWorkspace(id: item.id, value: item.label) }
                                    Button("Move up") { model.perform(.workspaceMove(id: item.id, insertIndex: max(0, index - 1))) }
                                        .disabled(index == 0)
                                    Button("Move down") { model.perform(.workspaceMove(id: item.id, insertIndex: min(summaries.count - 1, index + 1))) }
                                        .disabled(index == summaries.count - 1)
                                    Divider()
                                    Button("Close workspace", role: .destructive) {
                                        closeWorkspace = projection.workspaces.first { $0.id == item.id }
                                    }
                                }
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
            if let item = closeWorkspace { Button("Close \(item.label)", role: .destructive) { model.perform(.workspaceClose(id: item.id), confirmDestructive: true); closeWorkspace = nil } }
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
    let zenPaneID: String?
    let paneGap: Double
    let terminalFontSize: Double
    let fileBrowserEnabled: Bool
    let enterZen: (String) -> Void
    let createWorkspace: () -> Void
    let requestSplit: (String, SplitDirection) -> Void
    let requestMoveToNewTab: (String, String) -> Void
    let requestClose: (PendingClose) -> Void
    @State private var editor: ProductEditor?
    @State private var focusState = TerminalFocusStateMachine()
    @Environment(\.bessieDensity) private var density

    private var workspace: WorkspaceProjection? {
        projection.workspaces.first { $0.id == selectedWorkspaceID } ?? projection.focusedWorkspace ?? projection.workspaces.first
    }
    private var tabs: [TabProjection] { projection.tabs.filter { $0.workspaceID == workspace?.id } }
    private var tab: TabProjection? {
        if let selectedPaneID,
           let selectedTabID = projection.panes.first(where: { $0.id == selectedPaneID })?.tabID,
           let selectedTab = tabs.first(where: { $0.id == selectedTabID }) {
            return selectedTab
        }
        return tabs.first { $0.focused } ?? tabs.first
    }
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
            if fileBrowserEnabled, model.activeConnection.kind == .ssh, model.remoteFileAccess == nil { RemoteWorkspaceFilesBanner() }

            if let tab, let layout = projection.layouts[tab.id] {
                let presentationNode = zenPaneID.flatMap { layout.root.isolatedPane($0) } ?? layout.root
                ProductPaneLayout(
                    node: presentationNode,
                    tabID: tab.id,
                    panes: projection.panes,
                    selectedPaneID: $selectedPaneID,
                    outlinedPaneID: focusState.outlinedPaneID,
                    zenPaneID: zenPaneID,
                    registry: registry,
                    gap: paneGap,
                    terminalFontSize: terminalFontSize,
                    dividerEnabled: zenPaneID == nil && !layout.zoomed && !model.actionInFlight,
                    focus: requestPaneFocus,
                    responderChanged: { paneID, isFirstResponder in
                        focusState.responderChanged(paneID: paneID, isFirstResponder: isFirstResponder)
                    },
                    edit: { editor = $0 },
                    action: { model.perform($0) },
                    requestSplit: requestSplit,
                    moveChoices: { PaneMoveChoices(projection: projection, paneID: $0) },
                    requestMoveToNewTab: requestMoveToNewTab,
                    close: { requestClose(.pane($0)) },
                    enterZen: enterZen
                )
                .padding(paneGap)
            } else {
                ProductEmptyState(
                    symbol: workspace == nil ? "square.grid.2x2" : "rectangle.split.3x1",
                    title: workspace == nil ? "No workspaces yet" : "No panes in this tab",
                    detail: workspace == nil ? "Create a workspace to open a real Herdr shell." : "Create a tab from the title bar or split a pane from its context menu.",
                    actionTitle: "Create workspace",
                    action: workspace == nil ? createWorkspace : nil
                )
                    .padding(7)
            }
        }
        .foregroundStyle(ProductPalette.strong)
        .background(Color.clear)
        .onAppear {
            selectedWorkspaceID = workspace?.id
            selectedPaneID = targetPaneID
            focusState.reconcile(authoritativePaneID: projection.focusedPane?.id)
        }
        .onChange(of: workspace?.id) { _, _ in selectedPaneID = targetPaneID }
        .onChange(of: tab?.id) { _, _ in selectedPaneID = targetPaneID }
        .onChange(of: projection.focusedPane?.id) { _, paneID in
            focusState.reconcile(authoritativePaneID: paneID)
        }
        .sheet(item: $editor) { ProductEditorSheet(editor: $0) { action in model.perform(action); editor = nil } }
    }

    private func requestPaneFocus(_ paneID: String) {
        selectedPaneID = paneID
        let request = focusState.beginRequest(paneID: paneID)
        registry.recordSwitchRequested(paneID: paneID)
        let refresh: PaneTerminalController.SurfaceRefresh =
            registry.controllers[paneID]?.isSurfacePresented == true ? .display : .full
        registry.focusWhenPresented(paneID: paneID, refresh: refresh)
        model.navigate([.paneFocus(id: paneID)]) { updatedProjection in
            guard focusState.complete(request, authoritativePaneID: updatedProjection.focusedPane?.id) else { return }
            registry.focusWhenPresented(paneID: paneID, refresh: .display)
        } failure: {
            focusState.fail(request)
        }
    }

}

private extension WorkspaceScope {
    var hierarchySection: WorkspaceHierarchySection? {
        switch self {
        case .selectedTab: nil
        case .allTabs: .tab
        case .allWorkspaces: .workspace
        case .allHerds: .herd
        }
    }
}

private struct RemoteWorkspaceFilesBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text("Remote files are unavailable. Terminals may still work.")
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(BessieDesign.subtle)
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(BessieDesign.inset)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
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
    @State private var topologyName = ""
    @State private var directory = NSHomeDirectory()
    @State private var arguments = ""
    @State private var placement: NewProcessPlacementChoice = .splitRight

    private var selectedAgent: AgentCatalogItem? { catalog.items.first { $0.kind == selectedKind } }
    private var canSubmit: Bool {
        let placementValid = placement == .newTab || targetPaneID != nil
        return placementValid
            && !topologyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!agentMode || selectedAgent?.availability.isAvailable == true)
    }

    var body: some View {
        ZStack {
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

                            BessieLabeledInput(label: placement == .newTab ? "Tab name" : "Pane name") {
                                TextField(placement == .newTab ? "tab-name" : "pane-name", text: $topologyName)
                                    .bessieInput()
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
        let normalizedTopologyName = topologyName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch placement {
        case .splitRight:
            launchPlacement = targetPaneID.map {
                .split(targetPaneID: $0, direction: .right, cwd: directory, name: normalizedTopologyName)
            }
        case .splitDown:
            launchPlacement = targetPaneID.map {
                .split(targetPaneID: $0, direction: .down, cwd: directory, name: normalizedTopologyName)
            }
        case .newTab:
            launchPlacement = .newTab(workspaceID: workspaceID, cwd: directory, name: normalizedTopologyName)
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
    let outlinedPaneID: String?
    let zenPaneID: String?
    @ObservedObject var registry: TerminalControllerRegistry
    let gap: Double
    let terminalFontSize: Double
    let dividerEnabled: Bool
    let focus: (String) -> Void
    let responderChanged: (String, Bool) -> Void
    let edit: (ProductEditor) -> Void
    let action: (HerdrAction) -> Void
    let requestSplit: (String, SplitDirection) -> Void
    let moveChoices: (String) -> PaneMoveChoices?
    let requestMoveToNewTab: (String, String) -> Void
    let close: (String) -> Void
    let enterZen: (String) -> Void

    var body: some View {
        switch node {
        case .pane(let leaf):
            ProductPane(
                leaf: leaf,
                pane: panes.first { $0.id == leaf.paneID },
                selected: outlinedPaneID == leaf.paneID,
                zenActive: zenPaneID == leaf.paneID,
                controller: registry.controllers[leaf.paneID],
                terminalFontSize: terminalFontSize,
                select: { selectedPaneID = leaf.paneID; focus(leaf.paneID) },
                responderChanged: { responderChanged(leaf.paneID, $0) },
                moveChoices: moveChoices(leaf.paneID),
                edit: edit,
                action: action,
                requestSplit: { requestSplit(leaf.paneID, $0) },
                requestMoveToNewTab: { requestMoveToNewTab(leaf.paneID, $0) },
                close: close,
                enterZen: enterZen
            )
        case .split(let branch):
            ProductSplitBranch(
                branch: branch,
                tabID: tabID,
                panes: panes,
                selectedPaneID: $selectedPaneID,
                outlinedPaneID: outlinedPaneID,
                zenPaneID: zenPaneID,
                registry: registry,
                gap: gap,
                terminalFontSize: terminalFontSize,
                dividerEnabled: dividerEnabled,
                focus: focus,
                responderChanged: responderChanged,
                edit: edit,
                action: action,
                requestSplit: requestSplit,
                moveChoices: moveChoices,
                requestMoveToNewTab: requestMoveToNewTab,
                close: close,
                enterZen: enterZen
            )
        }
    }
}

private struct ProductSplitBranch: View {
    let branch: PaneLayoutBranch
    let tabID: String
    let panes: [PaneProjection]
    @Binding var selectedPaneID: String?
    let outlinedPaneID: String?
    let zenPaneID: String?
    @ObservedObject var registry: TerminalControllerRegistry
    let gap: Double
    let terminalFontSize: Double
    let dividerEnabled: Bool
    let focus: (String) -> Void
    let responderChanged: (String, Bool) -> Void
    let edit: (ProductEditor) -> Void
    let action: (HerdrAction) -> Void
    let requestSplit: (String, SplitDirection) -> Void
    let moveChoices: (String) -> PaneMoveChoices?
    let requestMoveToNewTab: (String, String) -> Void
    let close: (String) -> Void
    let enterZen: (String) -> Void

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
            outlinedPaneID: outlinedPaneID,
            zenPaneID: zenPaneID,
            registry: registry,
            gap: gap,
            terminalFontSize: terminalFontSize,
            dividerEnabled: dividerEnabled,
            focus: focus,
            responderChanged: responderChanged,
            edit: edit,
            action: action,
            requestSplit: requestSplit,
            moveChoices: moveChoices,
            requestMoveToNewTab: requestMoveToNewTab,
            close: close,
            enterZen: enterZen
        )
    }

    private func divider(contentExtent: CGFloat) -> some View {
        Rectangle()
            .fill(hovering || dragOrigin != nil ? BessieDesign.strong.opacity(0.62) : BessieSemanticColor.clear)
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
            .accessibilityValue("\(Int(ratio * 100)) percent")
            .accessibilityHint("Drag or adjust to resize both panes")
            .accessibilityAdjustableAction { adjustment in
                guard dividerEnabled else { return }
                let delta: Double
                switch adjustment {
                case .increment: delta = 0.05
                case .decrement: delta = -0.05
                @unknown default: return
                }
                action(.setSplitRatio(
                    tabID: tabID,
                    path: branch.path,
                    ratio: min(0.9, max(0.1, ratio + delta))
                ))
            }
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
    let selected: Bool
    let zenActive: Bool
    let controller: PaneTerminalController?
    let terminalFontSize: Double
    let select: () -> Void
    let responderChanged: (Bool) -> Void
    let moveChoices: PaneMoveChoices?
    let edit: (ProductEditor) -> Void
    let action: (HerdrAction) -> Void
    let requestSplit: (SplitDirection) -> Void
    let requestMoveToNewTab: (String) -> Void
    let close: (String) -> Void
    let enterZen: (String) -> Void
    @State private var confirmingTakeover = false
    @Environment(\.bessieDensity) private var density

    private var semanticState: AgentSemanticState {
        AgentSemanticState(herdrValue: pane?.agentStatus ?? "unknown")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: select) {
                    HStack(spacing: 8) {
                        if pane?.agent == nil {
                            BessieIconView(icon: .terminalWindow, size: 13)
                                .accessibilityHidden(true)
                        } else {
                            BessieProviderMark(provider: pane?.agent)
                                .accessibilityHidden(true)
                        }
                        Text(pane?.presentationTitle ?? "Shell")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Focus \(pane?.presentationTitle ?? "pane"), \(HerdPresentationStatus(state: AgentSemanticState(herdrValue: pane?.agentStatus ?? "unknown")).rawValue)")
                .accessibilityValue(selected ? "Focused pane" : "Not focused")
                Button { enterZen(leaf.paneID) } label: {
                    BessieIconView(icon: .cornersOut, size: 12)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(zenActive ? "Exit Zen" : "Enter Zen")
                .accessibilityLabel("\(zenActive ? "Exit" : "Enter") Zen for \(pane?.presentationTitle ?? "pane")")
            }
            .foregroundStyle(ProductPalette.text)
            .padding(.leading, 9)
            .padding(.trailing, 6)
            .frame(height: density.paneHeaderHeight)
            .background(semanticState == .blocked ? BessieDesign.blocked.opacity(0.08) : (selected ? ProductPalette.selected : ProductPalette.panel))
            .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
            if let controller {
                RecoverableTerminalSurface(
                    controller: controller,
                    fontSize: terminalFontSize,
                    requestFocus: {
                        // Ghostty only makeFirstResponder's locally on click. A full
                        // Herdr pane.focus navigate on every mouseDown was breaking
                        // mouse-aware TUIs (async snapshot/refresh per click).
                        if selected {
                            controller.makeTerminalFirstResponder(refresh: .display)
                        } else {
                            select()
                        }
                    },
                    responderChanged: responderChanged
                )
                .onAppear {
                    controller.updateMouseCapture(agent: pane?.agent, foregroundCWD: pane?.foregroundCWD)
                }
                .onChange(of: pane?.agent) { _, agent in
                    controller.updateMouseCapture(agent: agent, foregroundCWD: pane?.foregroundCWD)
                }
                .onChange(of: pane?.foregroundCWD) { _, cwd in
                    controller.updateMouseCapture(agent: pane?.agent, foregroundCWD: cwd)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(BessieDesign.code)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.paneRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BessieDesign.paneRadius)
                .stroke(
                    selected ? BessieDesign.accent : (semanticState == .blocked ? BessieDesign.blocked.opacity(0.55) : ProductPalette.border),
                    lineWidth: 1
                )
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: BessieDesign.paneRadius + 2)
                    .stroke(BessieDesign.accentSoft, lineWidth: 3)
            }
        }
        .contextMenu { paneMenu }
        .alert("Take over this pane?", isPresented: $confirmingTakeover) {
            Button("Cancel", role: .cancel) {}
            Button("Take over", role: .destructive) { controller?.takeOver() }
        } message: {
            Text("The other terminal client will lose control of this pane.")
        }
    }

    @ViewBuilder private var paneMenu: some View {
        PaneContextMenuContent(
            paneID: leaf.paneID,
            primaryTitle: "Focus",
            primaryAction: select,
            zenTitle: "Enter Zen",
            enterZen: { enterZen(leaf.paneID) },
            action: action,
            requestSplit: requestSplit,
            moveChoices: moveChoices,
            requestMoveToNewTab: requestMoveToNewTab,
            canTakeOver: controller?.sessionMode == .observe && controller?.hasReadyFrame == true,
            requestTakeover: { confirmingTakeover = true },
            rename: { edit(.renamePane(id: leaf.paneID, value: pane?.label ?? "")) },
            close: { close(leaf.paneID) }
        )
    }
}

struct PaneContextMenuContent: View {
    let paneID: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let zenTitle: String
    let enterZen: () -> Void
    let action: (HerdrAction) -> Void
    let requestSplit: (SplitDirection) -> Void
    let moveChoices: PaneMoveChoices?
    let requestMoveToNewTab: (String) -> Void
    let canTakeOver: Bool
    let requestTakeover: () -> Void
    let rename: () -> Void
    let close: () -> Void

    var body: some View {
        Button(primaryTitle, action: primaryAction)
        Button(zenTitle, action: enterZen)
        Divider()
        Button("Split right") { requestSplit(.right) }
        Button("Split down") { requestSplit(.down) }
        Button("Zoom") { action(.paneZoom(id: paneID, mode: .toggle)) }
        Menu("Resize pane") {
            Button("Left") { action(.paneResize(id: paneID, direction: .left, amount: 0.05)) }
            Button("Right") { action(.paneResize(id: paneID, direction: .right, amount: 0.05)) }
            Button("Up") { action(.paneResize(id: paneID, direction: .up, amount: 0.05)) }
            Button("Down") { action(.paneResize(id: paneID, direction: .down, amount: 0.05)) }
        }
        if let moveChoices {
            PaneMoveMenuItems(
                paneID: paneID,
                choices: moveChoices,
                action: action,
                requestMoveToNewTab: requestMoveToNewTab
            )
        }
        if canTakeOver {
            Divider()
            Button("Take over terminal control", action: requestTakeover)
        }
        Button("Rename", action: rename)
        Divider()
        Button("Close pane", role: .destructive, action: close)
    }
}

private struct PaneMoveMenuItems: View {
    let paneID: String
    let choices: PaneMoveChoices
    let action: (HerdrAction) -> Void
    let requestMoveToNewTab: (String) -> Void

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
        if case .newTab(let workspaceID, _) = destination, let workspaceID {
            requestMoveToNewTab(workspaceID)
            return
        }
        action(.paneMove(id: paneID, destination: destination, focus: true))
    }
}

private struct RecoverableTerminalSurface: View {
    @ObservedObject var controller: PaneTerminalController
    let fontSize: Double
    var requestFocus: () -> Void = {}
    var responderChanged: (Bool) -> Void = { _ in }
    @State private var confirmingTakeover = false

    var body: some View {
        ZStack {
            GhosttyPaneSurface(
                controller: controller,
                fontSize: fontSize,
                requestFocus: requestFocus,
                responderChanged: responderChanged
            )
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
        case .failed(let reason):
            terminalMessage(
                title: "Terminal unavailable",
                detail: reason.isEmpty ? "Bessie couldn't open this terminal." : reason
            ) {
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
                .foregroundStyle(BessieDesign.codeText)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(BessieDesign.codeSubtle)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) { actions() }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BessieDesign.code)
    }
}

private enum ProductEditor: Identifiable {
    case createWorkspace
    case renameWorkspace(id: String, value: String)
    case renameTab(id: String, value: String)
    case renamePane(id: String, value: String)
    var id: String { switch self { case .createWorkspace: "create"; case .renameWorkspace(let id, _): "workspace-\(id)"; case .renameTab(let id, _): "tab-\(id)"; case .renamePane(let id, _): "pane-\(id)" } }
}

private struct TopologyNameSheet: View {
    let request: NamedTopologyRequest
    let submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.title).font(.system(size: 20, weight: .medium))
            TextField(request.fieldLabel, text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    submit(normalizedName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

private struct ProductEditorSheet: View {
    let editor: ProductEditor
    let submit: (HerdrAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 20, weight: .medium))
            if case .createWorkspace = editor {
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
        case .createWorkspace:
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            return .workspaceCreate(
                cwd: nil,
                label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                focus: true
            )
        case .renameWorkspace(let id, _): return .workspaceRename(id: id, label: label)
        case .renameTab(let id, _): return .tabRename(id: id, label: label)
        case .renamePane(let id, _): return .paneRename(id: id, label: label.isEmpty ? nil : label)
        }
    }
}

private extension ProductEditor {
    var initialValue: String { switch self { case .createWorkspace: ""; case .renameWorkspace(_, let value), .renameTab(_, let value), .renamePane(_, let value): value } }
    var requiresLabel: Bool { switch self { case .renameWorkspace, .renameTab: true; default: false } }
    var actionTitle: String { switch self { case .createWorkspace: "Create"; default: "Save" } }
}

struct BessieActionPopover<Content: View>: View {
    let label: String
    @ViewBuilder let content: (@escaping () -> Void) -> Content
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "ellipsis")
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                content { presented = false }
            }
            .padding(7)
            .frame(minWidth: 190)
            .background(BessieDesign.panel)
        }
    }
}

struct BessiePopoverActionRow: View {
    let title: String
    let symbol: String
    var destructive = false
    var disabled = false
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: destructive ? .medium : .regular))
                .foregroundStyle(destructive ? BessieSemanticColor.red : BessieDesign.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(hovering || focused ? BessieDesign.selected : BessieSemanticColor.clear)
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovering = $0 }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(title)
    }
}

enum PendingClose {
    case workspace(String), tab(String), pane(String)
    func resolvedAction(in projection: HerdrSessionProjection) -> HerdrAction {
        switch self {
        case .workspace(let id): .workspaceClose(id: id)
        case .tab(let id):
            if projection.confirmationForClosingTab(id: id).cascadesToWorkspaceClose,
               let workspaceID = projection.tabs.first(where: { $0.id == id })?.workspaceID {
                .workspaceClose(id: workspaceID)
            } else {
                .tabClose(id: id)
            }
        case .pane(let id):
            if projection.confirmationForClosingPane(id: id).cascadesToWorkspaceClose,
               let workspaceID = projection.panes.first(where: { $0.id == id })?.workspaceID {
                .workspaceClose(id: workspaceID)
            } else {
                .paneClose(id: id)
            }
        }
    }
    func requiresIntentConfirmation(in projection: HerdrSessionProjection) -> Bool {
        if case .workspaceClose = resolvedAction(in: projection) { true } else { false }
    }
    var title: String { switch self { case .workspace: "Close workspace?"; case .tab: "Close tab?"; case .pane: "Close pane?" } }
    var buttonTitle: String { switch self { case .workspace: "Close workspace"; case .tab: "Close tab"; case .pane: "Close pane" } }
    func message(in projection: HerdrSessionProjection) -> String { switch self { case .workspace(let id): projection.confirmationForClosingWorkspace(id: id).message; case .tab(let id): projection.confirmationForClosingTab(id: id).message; case .pane(let id): projection.confirmationForClosingPane(id: id).message } }
    func parentWorkspaceID(in projection: HerdrSessionProjection) -> String? {
        switch self {
        case .workspace: nil
        case .tab(let id): projection.tabs.first { $0.id == id }?.workspaceID
        case .pane(let id): projection.panes.first { $0.id == id }?.workspaceID
        }
    }
}

private struct ProductSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(ProductPalette.faint) }
}

struct ProductEmptyState: View {
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
    var title: String { HerdPresentationStatus(state: self).rawValue }
}

private extension AgentAvailability {
    var detail: String {
        switch self {
        case .available: "Available"
        case .unavailable(let reason): reason
        }
    }
}

private struct RailResizeHandle: View {
    @Binding var width: CGFloat
    let gap: CGFloat
    @State private var dragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: gap)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStart == nil { dragStart = width }
                        let next = (dragStart ?? width) + value.translation.width
                        width = min(420, max(180, next))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityLabel("Resize sidebar")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(420, width + 12)
                case .decrement: width = max(180, width - 12)
                @unknown default: break
                }
            }
    }
}

private struct PaneControllerStatusLabel: View {
    @ObservedObject var controller: PaneTerminalController

    @ViewBuilder
    var body: some View {
        if controller.sessionMode == .observe && controller.hasReadyFrame {
            Text("Read only")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(ProductPalette.subtle)
        } else if !controller.status.productIsReady {
            Text(controller.status.productLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(ProductPalette.subtle)
        }
    }
}

private extension TerminalControllerStatus {
    var productLabel: String { switch self { case .starting: "Starting"; case .waitingForFull: "Syncing"; case .ready: "Live"; case .reconnecting: "Reconnecting"; case .ownershipConflict: "In use"; case .stopped: "Stopped"; case .failed: "Failed" } }
    var productIsReady: Bool {
        if case .ready = self { return true }
        return false
    }
    var zenNeedsRecovery: Bool {
        switch self {
        case .reconnecting, .ownershipConflict, .stopped, .failed: true
        case .starting, .waitingForFull, .ready: false
        }
    }
}

private extension View {
    func productTag() -> some View { self.font(.system(size: 8, weight: .bold)).padding(.horizontal, 5).frame(height: 16).overlay { Rectangle().stroke(ProductPalette.border, lineWidth: 1) }.foregroundStyle(ProductPalette.subtle) }
}
