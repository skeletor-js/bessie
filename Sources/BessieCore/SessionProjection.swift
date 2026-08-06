import Foundation

public struct WorkspaceProjection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let number: Int
    public let label: String
    public let focused: Bool
    public let paneCount: Int
    public let tabCount: Int
    public let activeTabID: String
    public let agentStatus: String
    enum CodingKeys: String, CodingKey {
        case id = "workspace_id", number, label, focused
        case paneCount = "pane_count", tabCount = "tab_count", activeTabID = "active_tab_id", agentStatus = "agent_status"
    }
}

public struct TabProjection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let workspaceID: String
    public let number: Int
    public let label: String
    public let focused: Bool
    public let paneCount: Int
    public let agentStatus: String
    enum CodingKeys: String, CodingKey {
        case id = "tab_id", workspaceID = "workspace_id", number, label, focused
        case paneCount = "pane_count", agentStatus = "agent_status"
    }
}

public struct PaneProjection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let terminalID: String
    public let workspaceID: String
    public let tabID: String
    public let focused: Bool
    public let label: String?
    public let cwd: String?
    public let foregroundCWD: String?
    public let agent: String?
    public let title: String?
    public let agentStatus: String
    public let revision: UInt64
    enum CodingKeys: String, CodingKey {
        case id = "pane_id", terminalID = "terminal_id", workspaceID = "workspace_id", tabID = "tab_id", focused, label, cwd, agent, title
        case foregroundCWD = "foreground_cwd"
        case agentStatus = "agent_status", revision
    }

    /// Prefer live process cwd, then Herdr pane cwd.
    public var effectiveCWD: String? {
        if let foregroundCWD, !foregroundCWD.isEmpty { return foregroundCWD }
        if let cwd, !cwd.isEmpty { return cwd }
        return nil
    }

    public var presentationTitle: String {
        for candidate in [label, agent, title] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        if let effectiveCWD {
            let folder = URL(fileURLWithPath: effectiveCWD).lastPathComponent
            if !folder.isEmpty { return folder }
        }
        return "Shell"
    }
}

public struct LayoutRect: Codable, Equatable, Sendable {
    public let x: Int; public let y: Int; public let width: Int; public let height: Int
}

public enum SplitDirection: String, Codable, Equatable, Sendable { case right, down }
public enum PaneDirection: String, Codable, Equatable, Sendable { case left, right, up, down }

public indirect enum RecursivePaneLayout: Equatable, Sendable {
    case pane(PaneLayoutLeaf)
    case split(PaneLayoutBranch)

    public var paneIDs: [String] {
        switch self {
        case .pane(let leaf): [leaf.paneID]
        case .split(let branch): branch.first.paneIDs + branch.second.paneIDs
        }
    }
}

public struct PaneLayoutLeaf: Equatable, Sendable {
    public let paneID: String
    public let focused: Bool
    public let rect: LayoutRect
}

public struct PaneLayoutBranch: Equatable, Sendable {
    public let id: String
    public let direction: SplitDirection
    public let ratio: Double
    public let rect: LayoutRect
    public let path: [Bool]
    public let first: RecursivePaneLayout
    public let second: RecursivePaneLayout
}

public struct TabLayoutProjection: Equatable, Sendable {
    public let workspaceID: String
    public let tabID: String
    public let zoomed: Bool
    public let focusedPaneID: String
    public let root: RecursivePaneLayout
}

public struct CloseConfirmation: Equatable, Sendable {
    public let isRequired: Bool
    public let affectedIDs: [String]
    public let cascadesToWorkspaceClose: Bool
    public let message: String
}

public struct FocusFallback: Equatable, Sendable {
    public let workspaceID: String?
    public let tabID: String?
    public let paneID: String?
}

public struct HerdrSessionProjection: Equatable, Sendable {
    public let snapshot: HerdrSnapshot
    public let workspaces: [WorkspaceProjection]
    public let tabs: [TabProjection]
    public let panes: [PaneProjection]
    public let agents: [AgentProjection]
    public let layouts: [String: TabLayoutProjection]

    public init(snapshot: HerdrSnapshot) throws {
        self.snapshot = snapshot
        workspaces = try snapshot.workspaces.map(Self.decode).sorted { $0.number < $1.number }
        tabs = try snapshot.tabs.map(Self.decode).sorted { $0.number < $1.number }
        panes = try snapshot.panes.map(Self.decode)
        let panesByID = Dictionary(panes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let authoritativeAgents: [AgentProjection] = try snapshot.agents.map(Self.decode)
        agents = authoritativeAgents.map { $0.merging(pane: panesByID[$0.id]) }
        let decodedLayouts: [WireLayout] = try snapshot.layouts.map(Self.decode)
        layouts = try Dictionary(uniqueKeysWithValues: decodedLayouts.map { layout in
            (layout.tabID, try Self.project(layout))
        })
    }

    public var focusedWorkspace: WorkspaceProjection? {
        workspaces.first { $0.id == snapshot.focusedWorkspaceID } ?? workspaces.first { $0.focused }
    }
    public var focusedTab: TabProjection? {
        tabs.first { $0.id == snapshot.focusedTabID } ?? tabs.first { $0.focused }
    }
    public var focusedPane: PaneProjection? {
        panes.first { $0.id == snapshot.focusedPaneID } ?? panes.first { $0.focused }
    }

    /// Bessie-local focus rewrite used for optimistic navigation before Herdr's
    /// snapshot returns. Does not invent entities — only retargets focus flags.
    public func applyingLocalFocus(
        workspaceID: String? = nil,
        tabID: String? = nil,
        paneID: String? = nil
    ) throws -> HerdrSessionProjection {
        let resolvedPane = paneID.flatMap { id in panes.first { $0.id == id } }
        let resolvedTabID = tabID
            ?? resolvedPane?.tabID
            ?? snapshot.focusedTabID
        let resolvedWorkspaceID = workspaceID
            ?? resolvedPane?.workspaceID
            ?? tabs.first { $0.id == resolvedTabID }?.workspaceID
            ?? snapshot.focusedWorkspaceID
        let resolvedPaneID = paneID
            ?? (resolvedTabID.flatMap { tab in
                panes.first { $0.tabID == tab && $0.focused }?.id
                    ?? panes.first { $0.tabID == tab }?.id
            })
            ?? snapshot.focusedPaneID

        let nextSnapshot = HerdrSnapshot(
            version: snapshot.version,
            protocolVersion: snapshot.protocolVersion,
            focusedWorkspaceID: resolvedWorkspaceID,
            focusedTabID: resolvedTabID,
            focusedPaneID: resolvedPaneID,
            workspaces: Self.rewritingFocused(
                snapshot.workspaces,
                idKey: "workspace_id",
                focusedID: resolvedWorkspaceID
            ),
            tabs: Self.rewritingFocused(
                snapshot.tabs,
                idKey: "tab_id",
                focusedID: resolvedTabID
            ),
            panes: Self.rewritingFocused(
                snapshot.panes,
                idKey: "pane_id",
                focusedID: resolvedPaneID
            ),
            layouts: Self.rewritingLayoutFocus(
                snapshot.layouts,
                tabID: resolvedTabID,
                paneID: resolvedPaneID
            ),
            agents: snapshot.agents
        )
        return try HerdrSessionProjection(snapshot: nextSnapshot)
    }

    /// Collapse a navigation action list against the current authoritative focus so
    /// already-focused workspace/tab/pane hops skip useless Herdr RPCs.
    public func prunedNavigationActions(_ actions: [HerdrAction]) -> [HerdrAction] {
        actions.filter { action in
            switch action {
            case .workspaceFocus(let id):
                return focusedWorkspace?.id != id
            case .tabFocus(let id):
                return focusedTab?.id != id
            case .paneFocus(let id):
                return focusedPane?.id != id
            default:
                return true
            }
        }
    }

    public func applyingNavigationActions(_ actions: [HerdrAction]) throws -> HerdrSessionProjection? {
        var workspaceID = snapshot.focusedWorkspaceID
        var tabID = snapshot.focusedTabID
        var paneID = snapshot.focusedPaneID
        var sawFocus = false
        for action in actions {
            switch action {
            case .workspaceFocus(let id):
                workspaceID = id
                sawFocus = true
            case .tabFocus(let id):
                tabID = id
                if let tab = tabs.first(where: { $0.id == id }) {
                    workspaceID = tab.workspaceID
                }
                sawFocus = true
            case .paneFocus(let id):
                paneID = id
                if let pane = panes.first(where: { $0.id == id }) {
                    tabID = pane.tabID
                    workspaceID = pane.workspaceID
                }
                sawFocus = true
            default:
                return nil
            }
        }
        guard sawFocus else { return nil }
        return try applyingLocalFocus(workspaceID: workspaceID, tabID: tabID, paneID: paneID)
    }

    private static func rewritingFocused(
        _ values: [JSONValue],
        idKey: String,
        focusedID: String?
    ) -> [JSONValue] {
        values.map { value in
            guard case .object(var object) = value,
                  case .string(let id) = object[idKey]
            else { return value }
            object["focused"] = .bool(id == focusedID)
            return .object(object)
        }
    }

    private static func rewritingLayoutFocus(
        _ values: [JSONValue],
        tabID: String?,
        paneID: String?
    ) -> [JSONValue] {
        guard let tabID, let paneID else { return values }
        return values.map { value in
            guard case .object(var object) = value,
                  case .string(let layoutTabID) = object["tab_id"],
                  layoutTabID == tabID
            else { return value }
            object["focused_pane_id"] = .string(paneID)
            return .object(object)
        }
    }

    public func confirmationForClosingWorkspace(id: String) -> CloseConfirmation {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            return CloseConfirmation(isRequired: false, affectedIDs: [], cascadesToWorkspaceClose: false, message: "This workspace is no longer available.")
        }
        let affectedPanes = panes.filter { $0.workspaceID == id }
        return CloseConfirmation(
            isRequired: !affectedPanes.isEmpty,
            affectedIDs: [workspace.id] + affectedPanes.map(\.id),
            cascadesToWorkspaceClose: true,
            message: "This will stop processes in \(affectedPanes.count) pane\(affectedPanes.count == 1 ? "" : "s"). Closing Bessie alone leaves them running."
        )
    }

    public func confirmationForClosingTab(id: String) -> CloseConfirmation {
        guard let tab = tabs.first(where: { $0.id == id }) else {
            return CloseConfirmation(isRequired: false, affectedIDs: [], cascadesToWorkspaceClose: false, message: "This tab is no longer available.")
        }
        let affectedPanes = panes.filter { $0.tabID == id }
        let finalTab = tabs.filter { $0.workspaceID == tab.workspaceID }.count == 1
        let cascade = finalTab ? " This is the last tab, so the workspace will also close." : ""
        return CloseConfirmation(
            isRequired: !affectedPanes.isEmpty,
            affectedIDs: [tab.id] + affectedPanes.map(\.id),
            cascadesToWorkspaceClose: finalTab,
            message: "This will stop processes in \(affectedPanes.count) pane\(affectedPanes.count == 1 ? "" : "s").\(cascade) Closing Bessie alone leaves them running."
        )
    }

    public func confirmationForClosingPane(id: String) -> CloseConfirmation {
        guard let pane = panes.first(where: { $0.id == id }) else {
            return CloseConfirmation(isRequired: false, affectedIDs: [], cascadesToWorkspaceClose: false, message: "This pane is no longer available.")
        }
        let finalPane = panes.filter { $0.workspaceID == pane.workspaceID }.count == 1
        let cascade = finalPane ? " This is the last pane, so its workspace may also close." : ""
        return CloseConfirmation(
            isRequired: true,
            affectedIDs: [pane.id],
            cascadesToWorkspaceClose: finalPane,
            message: "This will stop the pane's process.\(cascade) Closing Bessie alone leaves it running."
        )
    }

    public func focusFallback(preferredWorkspaceID: String?) -> FocusFallback {
        let workspace = workspaces.first { $0.id == preferredWorkspaceID } ?? focusedWorkspace ?? workspaces.first
        let tab = tabs.first { $0.workspaceID == workspace?.id && $0.id == snapshot.focusedTabID }
            ?? tabs.first { $0.workspaceID == workspace?.id && $0.focused }
            ?? tabs.first { $0.workspaceID == workspace?.id }
        let pane = panes.first { $0.tabID == tab?.id && $0.id == snapshot.focusedPaneID }
            ?? panes.first { $0.tabID == tab?.id && $0.focused }
            ?? panes.first { $0.tabID == tab?.id }
        return FocusFallback(workspaceID: workspace?.id, tabID: tab?.id, paneID: pane?.id)
    }

    private static func decode<T: Decodable>(_ value: JSONValue) throws -> T { try value.decode() }

    private static func project(_ layout: WireLayout) throws -> TabLayoutProjection {
        let splits = Dictionary(uniqueKeysWithValues: layout.splits.map { (parsePath($0.id), $0) })
        let root = try build(path: [], candidates: layout.panes, splits: splits)
        return TabLayoutProjection(workspaceID: layout.workspaceID, tabID: layout.tabID, zoomed: layout.zoomed, focusedPaneID: layout.focusedPaneID, root: root)
    }

    private static func build(path: [Bool], candidates: [WirePane], splits: [[Bool]: WireSplit]) throws -> RecursivePaneLayout {
        guard let split = splits[path] else {
            guard candidates.count == 1, let pane = candidates.first else {
                throw HerdrClientError.unexpectedResponse("layout path \(path) does not resolve to one pane")
            }
            return .pane(PaneLayoutLeaf(paneID: pane.paneID, focused: pane.focused, rect: pane.rect))
        }
        let splitCells = split.direction == .right
            ? (Float(split.rect.width) * Float(split.ratio)).rounded()
            : (Float(split.rect.height) * Float(split.ratio)).rounded()
        let boundary = split.direction == .right
            ? Double(split.rect.x) + Double(splitCells)
            : Double(split.rect.y) + Double(splitCells)
        let firstCandidates = candidates.filter {
            split.direction == .right ? Double($0.rect.x) + Double($0.rect.width) / 2 < boundary : Double($0.rect.y) + Double($0.rect.height) / 2 < boundary
        }
        let secondCandidates = candidates.filter { pane in !firstCandidates.contains(where: { $0.paneID == pane.paneID }) }
        return .split(PaneLayoutBranch(
            id: split.id, direction: split.direction, ratio: split.ratio, rect: split.rect, path: path,
            first: try build(path: path + [false], candidates: firstCandidates, splits: splits),
            second: try build(path: path + [true], candidates: secondCandidates, splits: splits)
        ))
    }

    private static func parsePath(_ id: String) -> [Bool] {
        guard let suffix = id.split(separator: "_").last, suffix != "root" else { return [] }
        return suffix.map { $0 == "1" }
    }
}

private struct WireLayout: Codable {
    let workspaceID: String; let tabID: String; let zoomed: Bool; let focusedPaneID: String
    let panes: [WirePane]; let splits: [WireSplit]
    enum CodingKeys: String, CodingKey { case workspaceID = "workspace_id", tabID = "tab_id", zoomed, focusedPaneID = "focused_pane_id", panes, splits }
}
private struct WirePane: Codable, Equatable { let paneID: String; let focused: Bool; let rect: LayoutRect; enum CodingKeys: String, CodingKey { case paneID = "pane_id", focused, rect } }
private struct WireSplit: Codable { let id: String; let direction: SplitDirection; let ratio: Double; let rect: LayoutRect }
