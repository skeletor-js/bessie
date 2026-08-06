import Foundation

public enum BessieShortcutKey: Equatable, Sendable {
    case character(String)
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case backspace
    case forwardDelete
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
    case showHerd
    case showSettings
    case newProject
    case projectsPicker
    case saveCurrentWorkspaceAsProject
    case newWorkspace
    case renameWorkspace
    case closeWorkspace
    case workspacePicker
    case openNextNeedsYou
    case newTab
    case renameTab
    case previousTab
    case nextTab
    case previousPane
    case nextPane
    case previousRailPane
    case nextRailPane
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
    case toggleZen
    case exitZen
    case previousAgent
    case nextAgent
}

public enum BessieTerminalShortcutAction: Equatable, Sendable {
    case sendBytes(Data)
    case copyOrSendInterrupt
    case paste
    case clearScrollback
    case selectAll
    case selectPreviousCommandOutput
    case jumpToPrompt(Int)
}

public enum BessieShortcutHandling: Equatable, Sendable {
    case passthrough
    case command(BessieShortcutCommand)
    case terminalShortcut(BessieTerminalShortcutAction)
}

public enum BessieKeyPolicy: Equatable, Sendable {
    case passthrough
    case appCommand(BessieShortcutCommand)
    case terminalShortcut(BessieTerminalShortcutAction)
}

public struct BessieCommandDefinition: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let shortcut: String?
    public let command: BessieShortcutCommand
    public let keywords: String
    public let alternateCommand: BessieShortcutCommand?

    public init(
        title: String,
        detail: String,
        shortcut: String? = nil,
        command: BessieShortcutCommand,
        keywords: String = "",
        alternateCommand: BessieShortcutCommand? = nil
    ) {
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
        self.command = command
        self.keywords = keywords
        self.alternateCommand = alternateCommand
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
        if let action = terminalAction(for: stroke) {
            return .terminalShortcut(action)
        }
        if stroke.command, !stroke.control, !stroke.option, !stroke.shift,
           case .character(let raw) = stroke.key,
           ["q", "h", "m", "`"].contains(raw.lowercased()) {
            return .passthrough
        }

        switch BessieKeyboardShortcutRouter().handleProductCommand(stroke) {
        case .passthrough: return .passthrough
        case .command(let command): return .appCommand(command)
        case .terminalShortcut(let action): return .terminalShortcut(action)
        }
    }

    public func handle(_ stroke: BessieShortcutStroke) -> BessieShortcutHandling {
        switch Self.policy(for: stroke) {
        case .passthrough: return .passthrough
        case .appCommand(let command): return .command(command)
        case .terminalShortcut(let action): return .terminalShortcut(action)
        }
    }

    private static func terminalAction(for stroke: BessieShortcutStroke) -> BessieTerminalShortcutAction? {
        // Ghostty macos-option-as-alt word motion (Option alone, no Command).
        if stroke.option, !stroke.command, !stroke.control, !stroke.shift {
            switch stroke.key {
            case .leftArrow: return .sendBytes(Data([0x1b, 0x62])) // ESC b
            case .rightArrow: return .sendBytes(Data([0x1b, 0x66])) // ESC f
            default: break
            }
        }

        guard stroke.command, !stroke.control else { return nil }

        if case .character(let raw) = stroke.key, !stroke.option {
            switch (raw.lowercased(), stroke.shift) {
            case ("b", false): return .sendBytes(Data([0x02]))
            case ("c", false): return .copyOrSendInterrupt
            case ("v", false): return .paste
            case ("k", false): return .clearScrollback
            case ("a", false): return .selectAll
            case ("a", true): return .selectPreviousCommandOutput
            // Whole-line delete until terminal search exists (Ghostty ⌘G is search-next).
            case ("g", false): return .sendBytes(Data([0x01, 0x0b]))
            default: return nil
            }
        }

        guard !stroke.option else { return nil }
        switch stroke.key {
        case .upArrow: return .jumpToPrompt(-1)
        case .downArrow: return .jumpToPrompt(1)
        case .leftArrow where !stroke.shift: return .sendBytes(Data([0x01])) // Ghostty super+left
        case .rightArrow where !stroke.shift: return .sendBytes(Data([0x05])) // Ghostty super+right
        case .backspace where !stroke.shift: return .sendBytes(Data([0x15])) // Ghostty super+backspace
        case .forwardDelete where !stroke.shift: return .sendBytes(Data([0x0b])) // kill to EOL
        case .character, .leftArrow, .rightArrow, .backspace, .forwardDelete: return nil
        }
    }

    private func handleProductCommand(_ stroke: BessieShortcutStroke) -> BessieShortcutHandling {
        if !stroke.command, !stroke.control, stroke.option, !stroke.shift,
           case .character(let raw) = stroke.key, raw.lowercased() == "p" {
            return .command(.projectsPicker)
        }
        guard stroke.command else { return .passthrough }

        if case .character(let raw) = stroke.key {
            let key = raw.lowercased()
            if !stroke.control && !stroke.option {
                if let index = Int(key), (1...9).contains(index), !stroke.shift {
                    return .command(.switchTab(index))
                }
                switch (key, stroke.shift) {
                case ("p", true): return .command(.showCommandPalette)
                case (",", false): return .command(.showSettings)
                case ("n", false): return .command(.newWorkspace)
                case ("w", false): return .command(.closePane)
                case ("w", true): return .command(.closeWorkspace)
                case ("g", true): return .command(.workspacePicker)
                case ("t", false): return .command(.newTab)
                case ("[", false): return .command(.previousPane)
                case ("]", false): return .command(.nextPane)
                case ("[", true): return .command(.previousTab)
                case ("]", true): return .command(.nextTab)
                case ("\r", true): return .command(.zoomPane)
                case ("d", false): return .command(.splitPane(.right))
                case ("d", true): return .command(.splitPane(.down))
                case ("b", true): return .command(.toggleSidebar)
                case ("j", true): return .command(.nextRailPane)
                case ("k", true): return .command(.previousRailPane)
                case ("z", true): return .command(.toggleZen)
                default: break
                }
            }
            if stroke.option && !stroke.control {
                switch (key, stroke.shift) {
                case ("n", false): return .command(.openNextNeedsYou)
                case ("t", false): return .command(.renameTab)
                case ("r", false): return .command(.renamePane)
                case ("x", false): return .command(.closePane)
                case ("[", true): return .command(.previousAgent)
                case ("]", true): return .command(.nextAgent)
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
        case .character, .backspace, .forwardDelete: return .passthrough
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
        .init(title: "Command Palette", detail: "Search panes, workspaces, Projects, herds, and commands", shortcut: "⇧⌘P", command: .showCommandPalette, keywords: "search cmdk"),
        .init(title: "The herd", detail: "Open Bessie's live herd page", command: .showHerd, keywords: "home agents activity"),
        .init(title: "New project", detail: "Create a reusable local Project recipe", command: .newProject, keywords: "create project recipe"),
        .init(title: "Manage projects", detail: "Browse and edit local Project recipes", shortcut: "⌥P", command: .projectsPicker, keywords: "open project recipes offline"),
        .init(title: "Create project from current workspace…", detail: "Capture the focused Herdr layout as a new Project draft", command: .saveCurrentWorkspaceAsProject, keywords: "save project capture tabs panes layout"),
        .init(title: "New workspace", detail: "Create and focus a Herdr workspace", shortcut: "⌘N", command: .newWorkspace, keywords: "create"),
        .init(title: "Rename workspace", detail: "Rename the current workspace", command: .renameWorkspace),
        .init(title: "Close workspace", detail: "Close the current workspace and its processes", shortcut: "⇧⌘W", command: .closeWorkspace),
        .init(title: "Open Workspaces", detail: "Browse and focus a workspace", shortcut: "⇧⌘G", command: .workspacePicker, keywords: "goto switch"),
        .init(title: "New tab", detail: "Create a shell tab in the current workspace", shortcut: "⌘T", command: .newTab, keywords: "create"),
        .init(title: "Rename tab", detail: "Rename the current tab", shortcut: "⌥⌘T", command: .renameTab),
        .init(title: "Previous tab", detail: "Focus the previous tab", shortcut: "⇧⌘[", command: .previousTab),
        .init(title: "Next tab", detail: "Focus the next tab", shortcut: "⇧⌘]", command: .nextTab),
        .init(title: "Close tab", detail: "Close the current tab and its processes", command: .closeTab),
        .init(title: "Rename pane", detail: "Rename the focused pane", shortcut: "⌥⌘R", command: .renamePane),
        .init(title: "Previous pane", detail: "Focus the previous pane", shortcut: "⌘[", command: .previousPane),
        .init(title: "Next pane", detail: "Focus the next pane", shortcut: "⌘]", command: .nextPane),
        .init(title: "Previous pane in the herd", detail: "Open the previous available pane in rendered rail order", shortcut: "⇧⌘K", command: .previousRailPane),
        .init(title: "Next pane in the herd", detail: "Open the next available pane in rendered rail order", shortcut: "⇧⌘J", command: .nextRailPane),
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
        .init(title: "Close pane", detail: "Close the focused pane and its process", shortcut: "⌘W", command: .closePane),
        .init(title: "Zoom pane", detail: "Toggle zoom for the focused pane", shortcut: "⇧⌘↩", command: .zoomPane),
        .init(title: "Resize pane left", detail: "Nudge the focused pane left", shortcut: "⌃⌘←", command: .resizePane(.left)),
        .init(title: "Resize pane down", detail: "Nudge the focused pane down", shortcut: "⌃⌘↓", command: .resizePane(.down)),
        .init(title: "Resize pane up", detail: "Nudge the focused pane up", shortcut: "⌃⌘↑", command: .resizePane(.up)),
        .init(title: "Resize pane right", detail: "Nudge the focused pane right", shortcut: "⌃⌘→", command: .resizePane(.right)),
        .init(title: "Toggle sidebar", detail: "Show or hide Bessie's navigation", shortcut: "⇧⌘B", command: .toggleSidebar),
        .init(title: "Toggle Zen", detail: "Focus the selected real terminal with minimal chrome", shortcut: "⇧⌘Z", command: .toggleZen, keywords: "focus terminal presentation"),
        .init(title: "Exit Zen", detail: "Return to the workspace without changing Herdr topology", command: .exitZen, keywords: "leave focus terminal presentation"),
        .init(title: "Previous agent", detail: "Open the previous Herdr agent in authoritative order", shortcut: "⇧⌥⌘[", command: .previousAgent, keywords: "zen herd navigate"),
        .init(title: "Next agent", detail: "Open the next Herdr agent in authoritative order", shortcut: "⇧⌥⌘]", command: .nextAgent, keywords: "zen herd navigate"),
        .init(title: "Open next agent that needs you", detail: "Open the first blocked agent in The herd", shortcut: "⌥⌘N", command: .openNextNeedsYou, keywords: "needs you blocked herd"),
        .init(title: "Settings", detail: "Open Bessie settings", shortcut: "⌘,", command: .showSettings),
    ]
}

public enum BessieZenTransitionEffect: Equatable, Sendable {
    case presentationOnly
}

public enum BessieZenFocusIntent: Equatable, Sendable {
    case terminal(paneID: String, revision: UInt64)
}

public struct BessieZenPresentationState: Equatable, Sendable {
    public private(set) var isActive: Bool
    public private(set) var selectedPaneID: String?
    public private(set) var focusIntent: BessieZenFocusIntent?
    public private(set) var railWasCollapsed: Bool?
    private var focusRevision: UInt64

    public static let inactive = BessieZenPresentationState(
        isActive: false,
        selectedPaneID: nil,
        focusIntent: nil,
        railWasCollapsed: nil,
        focusRevision: 0
    )
    public static let transitionEffect = BessieZenTransitionEffect.presentationOnly

    public mutating func enter(paneID: String, railCollapsed: Bool = false) {
        guard !paneID.isEmpty else { return }
        if !isActive {
            railWasCollapsed = railCollapsed
        }
        isActive = true
        selectedPaneID = paneID
        requestTerminalFocus(paneID: paneID)
    }

    @discardableResult
    public mutating func exit(expandRail: Bool = false) -> Bool {
        guard isActive else { return expandRail ? false : railWasCollapsed ?? false }
        let restoredRailCollapsed = expandRail ? false : railWasCollapsed ?? false
        isActive = false
        // The caller re-focuses after the standard workspace layout is restored.
        focusIntent = nil
        railWasCollapsed = nil
        return restoredRailCollapsed
    }

    public mutating func select(paneID: String) {
        guard !paneID.isEmpty else { return }
        selectedPaneID = paneID
        requestTerminalFocus(paneID: paneID)
    }

    private mutating func requestTerminalFocus(paneID: String) {
        focusRevision &+= 1
        focusIntent = .terminal(paneID: paneID, revision: focusRevision)
    }
}

public enum BessieZenAgentDirection: Equatable, Sendable {
    case previous
    case next
}

public enum BessieZenAgentRouter {
    public static func needsYouElsewhereCount(
        focused: RoutedPaneTarget?,
        agents: [ConnectedAgentProjection],
        connectedConnectionIDs: Set<String>,
        scope: ConnectionScope = .all
    ) -> Int {
        liveAgents(agents, connectedConnectionIDs: connectedConnectionIDs, scope: scope).reduce(into: 0) { count, agent in
            guard AgentSemanticState(herdrValue: agent.agent.agentStatus).requiresUserAction,
                  agent.connectionID != focused?.connectionID || agent.paneID != focused?.paneID
            else { return }
            count += 1
        }
    }

    public static func target(
        direction: BessieZenAgentDirection,
        from current: RoutedPaneTarget?,
        agents: [ConnectedAgentProjection],
        connectedConnectionIDs: Set<String>,
        scope: ConnectionScope = .all
    ) -> RoutedPaneTarget? {
        let live = liveAgents(
            agents,
            connectedConnectionIDs: connectedConnectionIDs,
            scope: scope
        )
        guard !live.isEmpty else { return nil }
        let currentIndex = current.flatMap { target in
            live.firstIndex { agent in
                agent.connectionID == target.connectionID && agent.paneID == target.paneID
            }
        }
        let index: Int
        switch direction {
        case .previous:
            index = currentIndex.map { ($0 - 1 + live.count) % live.count } ?? live.count - 1
        case .next:
            index = currentIndex.map { ($0 + 1) % live.count } ?? 0
        }
        return live[index].routedPaneTarget
    }

    public static func nextNeedsYou(
        from current: RoutedPaneTarget?,
        agents: [ConnectedAgentProjection],
        connectedConnectionIDs: Set<String>,
        scope: ConnectionScope = .all
    ) -> RoutedPaneTarget? {
        let live = liveAgents(
            agents,
            connectedConnectionIDs: connectedConnectionIDs,
            scope: scope
        )
        guard !live.isEmpty else { return nil }
        let start = current.flatMap { target in
            live.firstIndex { agent in
                agent.connectionID == target.connectionID && agent.paneID == target.paneID
            }
        } ?? -1
        for offset in 1...live.count {
            let candidate = live[(start + offset) % live.count]
            if AgentSemanticState(herdrValue: candidate.agent.agentStatus).requiresUserAction {
                return candidate.routedPaneTarget
            }
        }
        return nil
    }

    private static func liveAgents(
        _ agents: [ConnectedAgentProjection],
        connectedConnectionIDs: Set<String>,
        scope: ConnectionScope
    ) -> [ConnectedAgentProjection] {
        agents.filter {
            connectedConnectionIDs.contains($0.connectionID)
                && scope.includes(connectionID: $0.connectionID)
        }
    }
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
