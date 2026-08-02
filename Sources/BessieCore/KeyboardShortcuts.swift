import Foundation

public enum BessieShortcutKey: Equatable, Sendable {
    case character(String)
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
}

public struct BessieShortcutStroke: Equatable, Sendable {
    public let key: BessieShortcutKey
    public let control: Bool
    public let option: Bool
    public let command: Bool
    public let shift: Bool

    public init(
        key: BessieShortcutKey,
        control: Bool = false,
        option: Bool = false,
        command: Bool = false,
        shift: Bool = false
    ) {
        self.key = key
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
    }
}

public enum BessieShortcutCommand: Equatable, Sendable {
    case showCommandPalette
    case showSettings
    case projectsPicker
    case saveCurrentWorkspaceAsProject
    case newWorkspace
    case renameWorkspace
    case closeWorkspace
    case workspacePicker
    case openNotificationTarget
    case newTab
    case renameTab
    case previousTab
    case nextTab
    case switchTab(Int)
    case closeTab
    case renamePane
    case focusPane(PaneDirection)
    case swapPane(PaneDirection)
    case splitPane(SplitDirection)
    case closePane
    case zoomPane
    case resizePane(PaneDirection)
    case toggleSidebar
}

public enum BessieShortcutHandling: Equatable, Sendable {
    case passthrough
    case command(BessieShortcutCommand)
}

public enum BessieKeyPolicy: Equatable, Sendable {
    case passthrough
    case appCommand(BessieShortcutCommand)
}

public struct BessieCommandDefinition: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let shortcut: String?
    public let command: BessieShortcutCommand
    public let keywords: String

    public init(
        title: String,
        detail: String,
        shortcut: String? = nil,
        command: BessieShortcutCommand,
        keywords: String = ""
    ) {
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
        self.command = command
        self.keywords = keywords
    }

    public func matches(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        let haystack = "\(title) \(detail) \(keywords)".lowercased()
        return normalized.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.contains($0) }
    }
}

public struct BessieKeyboardShortcutRouter: Equatable, Sendable {
    public init() {}

    /// AppKit retains ownership of standard application chords. Bessie only
    /// consumes the product commands listed below; terminal input gets every
    /// other stroke.
    public static func policy(for stroke: BessieShortcutStroke) -> BessieKeyPolicy {
        if stroke.command, !stroke.control, !stroke.option, !stroke.shift,
           case .character(let raw) = stroke.key,
           ["q", "h", "m", "`"].contains(raw.lowercased()) {
            return .passthrough
        }

        switch BessieKeyboardShortcutRouter().handleProductCommand(stroke) {
        case .passthrough: return .passthrough
        case .command(let command): return .appCommand(command)
        }
    }

    public func handle(_ stroke: BessieShortcutStroke) -> BessieShortcutHandling {
        switch Self.policy(for: stroke) {
        case .passthrough: return .passthrough
        case .appCommand(let command): return .command(command)
        }
    }

    private func handleProductCommand(_ stroke: BessieShortcutStroke) -> BessieShortcutHandling {
        guard stroke.command else { return .passthrough }

        if case .character(let raw) = stroke.key {
            let key = raw.lowercased()
            if !stroke.control && !stroke.option {
                if let index = Int(key), (1...9).contains(index), !stroke.shift {
                    return .command(.switchTab(index))
                }
                switch (key, stroke.shift) {
                case ("b", false): return .command(.showCommandPalette)
                case (",", false): return .command(.showSettings)
                case ("n", false): return .command(.newWorkspace)
                case ("w", false): return .command(.closeTab)
                case ("w", true): return .command(.closeWorkspace)
                case ("g", true): return .command(.workspacePicker)
                case ("t", false): return .command(.newTab)
                case ("[", false): return .command(.previousTab)
                case ("]", false): return .command(.nextTab)
                case ("d", false): return .command(.splitPane(.right))
                case ("d", true): return .command(.splitPane(.down))
                case ("b", true): return .command(.toggleSidebar)
                default: break
                }
            }
            if stroke.option && !stroke.control {
                switch (key, stroke.shift) {
                case ("n", false): return .command(.openNotificationTarget)
                case ("t", false): return .command(.renameTab)
                case ("r", false): return .command(.renamePane)
                case ("x", false): return .command(.closePane)
                case ("z", false): return .command(.zoomPane)
                default: break
                }
            }
            return .passthrough
        }

        let direction: PaneDirection
        switch stroke.key {
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .character: return .passthrough
        }

        if stroke.option && !stroke.control {
            return .command(stroke.shift ? .swapPane(direction) : .focusPane(direction))
        }
        if stroke.control && !stroke.option && !stroke.shift {
            return .command(.resizePane(direction))
        }
        return .passthrough
    }

    public static let commands: [BessieCommandDefinition] = [
        .init(title: "Open Projects", detail: "Browse and edit local Project recipes", command: .projectsPicker, keywords: "project recipes offline"),
        .init(title: "Save current workspace as project…", detail: "Capture the focused Herdr layout as a new Project draft", command: .saveCurrentWorkspaceAsProject, keywords: "project capture tabs panes layout"),
        .init(title: "New workspace", detail: "Create and focus a Herdr workspace", shortcut: "⌘N", command: .newWorkspace, keywords: "create"),
        .init(title: "Rename workspace", detail: "Rename the current workspace", command: .renameWorkspace),
        .init(title: "Close workspace", detail: "Close the current workspace and its processes", shortcut: "⇧⌘W", command: .closeWorkspace),
        .init(title: "Open Workspaces", detail: "Browse and focus a workspace", shortcut: "⇧⌘G", command: .workspacePicker, keywords: "goto switch"),
        .init(title: "New tab", detail: "Create a shell tab in the current workspace", shortcut: "⌘T", command: .newTab, keywords: "create"),
        .init(title: "Rename tab", detail: "Rename the current tab", shortcut: "⌥⌘T", command: .renameTab),
        .init(title: "Previous tab", detail: "Focus the previous tab", shortcut: "⌘[", command: .previousTab),
        .init(title: "Next tab", detail: "Focus the next tab", shortcut: "⌘]", command: .nextTab),
        .init(title: "Close tab", detail: "Close the current tab and its processes", shortcut: "⌘W", command: .closeTab),
        .init(title: "Rename pane", detail: "Rename the focused pane", shortcut: "⌥⌘R", command: .renamePane),
        .init(title: "Focus pane left", detail: "Move focus to the pane on the left", shortcut: "⌥⌘←", command: .focusPane(.left)),
        .init(title: "Focus pane down", detail: "Move focus to the pane below", shortcut: "⌥⌘↓", command: .focusPane(.down)),
        .init(title: "Focus pane up", detail: "Move focus to the pane above", shortcut: "⌥⌘↑", command: .focusPane(.up)),
        .init(title: "Focus pane right", detail: "Move focus to the pane on the right", shortcut: "⌥⌘→", command: .focusPane(.right)),
        .init(title: "Swap pane left", detail: "Swap the focused pane with the pane on the left", shortcut: "⇧⌥⌘←", command: .swapPane(.left)),
        .init(title: "Swap pane down", detail: "Swap the focused pane with the pane below", shortcut: "⇧⌥⌘↓", command: .swapPane(.down)),
        .init(title: "Swap pane up", detail: "Swap the focused pane with the pane above", shortcut: "⇧⌥⌘↑", command: .swapPane(.up)),
        .init(title: "Swap pane right", detail: "Swap the focused pane with the pane on the right", shortcut: "⇧⌥⌘→", command: .swapPane(.right)),
        .init(title: "Split pane right", detail: "Open a shell pane to the right", shortcut: "⌘D", command: .splitPane(.right)),
        .init(title: "Split pane down", detail: "Open a shell pane below", shortcut: "⇧⌘D", command: .splitPane(.down)),
        .init(title: "Close pane", detail: "Close the focused pane and its process", shortcut: "⌥⌘X", command: .closePane),
        .init(title: "Zoom pane", detail: "Toggle zoom for the focused pane", shortcut: "⌥⌘Z", command: .zoomPane),
        .init(title: "Resize pane left", detail: "Nudge the focused pane left", shortcut: "⌃⌘←", command: .resizePane(.left)),
        .init(title: "Resize pane down", detail: "Nudge the focused pane down", shortcut: "⌃⌘↓", command: .resizePane(.down)),
        .init(title: "Resize pane up", detail: "Nudge the focused pane up", shortcut: "⌃⌘↑", command: .resizePane(.up)),
        .init(title: "Resize pane right", detail: "Nudge the focused pane right", shortcut: "⌃⌘→", command: .resizePane(.right)),
        .init(title: "Toggle sidebar", detail: "Show or hide Bessie's navigation", shortcut: "⇧⌘B", command: .toggleSidebar),
        .init(title: "Open next attention item", detail: "Open the first pane that needs you", shortcut: "⌥⌘N", command: .openNotificationTarget, keywords: "notification blocked done"),
        .init(title: "Settings", detail: "Open Bessie settings", shortcut: "⌘,", command: .showSettings),
    ]
}

public enum BessiePaneNavigation {
    public static func target(
        from paneID: String,
        direction: PaneDirection,
        in layout: RecursivePaneLayout
    ) -> String? {
        let leaves = flatten(layout)
        guard let origin = leaves.first(where: { $0.paneID == paneID }) else { return nil }
        let ox = Double(origin.rect.x) + Double(origin.rect.width) / 2
        let oy = Double(origin.rect.y) + Double(origin.rect.height) / 2

        let target = leaves
            .filter { candidate in
                guard candidate.paneID != paneID else { return false }
                let cx = Double(candidate.rect.x) + Double(candidate.rect.width) / 2
                let cy = Double(candidate.rect.y) + Double(candidate.rect.height) / 2
                switch direction {
                case .left: return cx < ox
                case .right: return cx > ox
                case .up: return cy < oy
                case .down: return cy > oy
                }
            }
            .min { lhs, rhs in score(lhs, origin: origin, direction: direction) < score(rhs, origin: origin, direction: direction) }
        return target?.paneID
    }

    private static func flatten(_ layout: RecursivePaneLayout) -> [PaneLayoutLeaf] {
        switch layout {
        case .pane(let leaf): return [leaf]
        case .split(let branch): return flatten(branch.first) + flatten(branch.second)
        }
    }

    private static func score(_ candidate: PaneLayoutLeaf, origin: PaneLayoutLeaf, direction: PaneDirection) -> Double {
        let ox = Double(origin.rect.x) + Double(origin.rect.width) / 2
        let oy = Double(origin.rect.y) + Double(origin.rect.height) / 2
        let cx = Double(candidate.rect.x) + Double(candidate.rect.width) / 2
        let cy = Double(candidate.rect.y) + Double(candidate.rect.height) / 2
        let primary = direction == .left || direction == .right ? abs(cx - ox) : abs(cy - oy)
        let secondary = direction == .left || direction == .right ? abs(cy - oy) : abs(cx - ox)
        return primary + secondary * 2
    }
}
