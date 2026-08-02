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
        let authoritativeIDs = Set(authoritativeAgents.map(\.id))
        let legacyAgents = panes.filter { $0.agent != nil && !authoritativeIDs.contains($0.id) }.map(AgentProjection.init(pane:))
        agents = authoritativeAgents.map { $0.merging(pane: panesByID[$0.id]) } + legacyAgents
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
