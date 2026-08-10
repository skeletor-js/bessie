import Foundation

public enum BessieShortcutKey: Equatable, Hashable, Sendable {
    case character(String)
    case escape
    case tab
    case backtab
    case enter
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case home
    case end
    case pageUp
    case pageDown
    case function(Int)
    case minus
    case keypadMinus
    case backspace
    case forwardDelete
}

public enum BessieShortcutEventPhase: Equatable, Hashable, Sendable {
    case keyDown
    case keyUp
    case modifierOnly
}

public struct BessieShortcutStroke: Equatable, Hashable, Sendable {
    public let key: BessieShortcutKey
    public let control: Bool
    public let option: Bool
    public let command: Bool
    public let shift: Bool
    public let layoutCharacter: String?
    public let phase: BessieShortcutEventPhase
    public let isRepeat: Bool

    public init(
        key: BessieShortcutKey,
        control: Bool = false,
        option: Bool = false,
        command: Bool = false,
        shift: Bool = false,
        layoutCharacter: String? = nil,
        phase: BessieShortcutEventPhase = .keyDown,
        isRepeat: Bool = false
    ) {
        self.key = key
        self.control = control
        self.option = option
        self.command = command
        self.shift = shift
        self.layoutCharacter = layoutCharacter
        self.phase = phase
        self.isRepeat = isRepeat
    }
}

public enum BessieShortcutCommand: Equatable, Sendable {
    case showCommandPalette
    case showKeyboardReference
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
    case copy
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
            case ("c", false): return .copy
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
        case .character, .escape, .tab, .backtab, .enter,
             .leftArrow, .rightArrow, .home, .end, .pageUp, .pageDown,
             .function, .minus, .keypadMinus, .backspace, .forwardDelete:
            return nil
        }
    }

    private func handleProductCommand(_ stroke: BessieShortcutStroke) -> BessieShortcutHandling {
        if stroke.command, !stroke.control, stroke.option, !stroke.shift,
           case .character(let raw) = stroke.key, raw.lowercased() == "p" {
            return .command(.projectsPicker)
        }
        guard stroke.command else { return .passthrough }

        if case .character(let raw) = stroke.key {
            let key = raw.lowercased()
            if !stroke.control && !stroke.option {
                switch (key, stroke.shift) {
                case ("p", true): return .command(.showCommandPalette)
                case (",", false): return .command(.showSettings)
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
                case ("[", true): return .command(.previousAgent)
                case ("]", true): return .command(.nextAgent)
                default: break
                }
            }
            return .passthrough
        }
        return .passthrough
    }

    public static let commands: [BessieCommandDefinition] = [
        .init(title: "Command Palette", detail: "Search panes, workspaces, Projects, herds, and commands", shortcut: "⇧⌘P", command: .showCommandPalette, keywords: "search cmdk"),
        .init(title: "Keyboard reference", detail: "Show Herdr prefix commands and Bessie application shortcuts", command: .showKeyboardReference, keywords: "help keys ctrl-b prefix"),
        .init(title: "The herd", detail: "Open Bessie's live herd page", command: .showHerd, keywords: "home agents activity"),
        .init(title: "Create project", detail: "Create a reusable Project recipe", command: .newProject, keywords: "new project recipe"),
        .init(title: "Manage projects", detail: "Browse and edit Project recipes", shortcut: "⌥⌘P", command: .projectsPicker, keywords: "open project recipes offline"),
        .init(title: "Create project from current workspace…", detail: "Capture the focused Herdr layout as a new Project draft", command: .saveCurrentWorkspaceAsProject, keywords: "save project capture tabs panes layout"),
        .init(title: "New workspace", detail: "Create and focus a Herdr workspace", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .newWorkspace), command: .newWorkspace, keywords: "create"),
        .init(title: "Rename workspace", detail: "Rename the current workspace", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .renameWorkspace), command: .renameWorkspace),
        .init(title: "Close workspace", detail: "Close the current workspace and its processes", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .closeWorkspace), command: .closeWorkspace),
        .init(title: "Open Workspaces", detail: "Browse and focus a workspace", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .showWorkspacePicker), command: .workspacePicker, keywords: "goto switch"),
        .init(title: "New tab", detail: "Create a shell tab in the current workspace", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .newTab), command: .newTab, keywords: "create"),
        .init(title: "Rename tab", detail: "Rename the current tab", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .renameTab), command: .renameTab),
        .init(title: "Previous tab", detail: "Focus the previous tab", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .previousTab), command: .previousTab),
        .init(title: "Next tab", detail: "Focus the next tab", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .nextTab), command: .nextTab),
        .init(title: "Close tab", detail: "Close the current tab and its processes", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .closeTab), command: .closeTab),
        .init(title: "Rename pane", detail: "Rename the focused pane", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .renamePane), command: .renamePane),
        .init(title: "Previous pane", detail: "Focus the previous pane", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .cyclePane(.previous)), command: .previousPane),
        .init(title: "Next pane", detail: "Focus the next pane", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .cyclePane(.next)), command: .nextPane),
        .init(title: "Previous pane in the herd", detail: "Open the previous available pane in rendered rail order", shortcut: "⇧⌘K", command: .previousRailPane),
        .init(title: "Next pane in the herd", detail: "Open the next available pane in rendered rail order", shortcut: "⇧⌘J", command: .nextRailPane),
        .init(title: "Focus pane left", detail: "Move focus to the pane on the left", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .focusPane(.left)), command: .focusPane(.left)),
        .init(title: "Focus pane down", detail: "Move focus to the pane below", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .focusPane(.down)), command: .focusPane(.down)),
        .init(title: "Focus pane up", detail: "Move focus to the pane above", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .focusPane(.up)), command: .focusPane(.up)),
        .init(title: "Focus pane right", detail: "Move focus to the pane on the right", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .focusPane(.right)), command: .focusPane(.right)),
        .init(title: "Swap pane left", detail: "Swap the focused pane with the pane on the left", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .swapPane(.left)), command: .swapPane(.left)),
        .init(title: "Swap pane down", detail: "Swap the focused pane with the pane below", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .swapPane(.down)), command: .swapPane(.down)),
        .init(title: "Swap pane up", detail: "Swap the focused pane with the pane above", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .swapPane(.up)), command: .swapPane(.up)),
        .init(title: "Swap pane right", detail: "Swap the focused pane with the pane on the right", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .swapPane(.right)), command: .swapPane(.right)),
        .init(title: "Split pane right", detail: "Open a shell pane to the right", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .splitPane(.right)), command: .splitPane(.right)),
        .init(title: "Split pane down", detail: "Open a shell pane below", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .splitPane(.down)), command: .splitPane(.down)),
        .init(title: "Close pane", detail: "Close the focused pane and its process", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .closePane), command: .closePane),
        .init(title: "Zoom pane", detail: "Toggle zoom for the focused pane", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .toggleZoom), command: .zoomPane),
        .init(title: "Resize pane left", detail: "Nudge the focused pane left", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .resizePane(.left)), command: .resizePane(.left)),
        .init(title: "Resize pane down", detail: "Nudge the focused pane down", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .resizePane(.down)), command: .resizePane(.down)),
        .init(title: "Resize pane up", detail: "Nudge the focused pane up", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .resizePane(.up)), command: .resizePane(.up)),
        .init(title: "Resize pane right", detail: "Nudge the focused pane right", shortcut: HerdrPrefixCommandCatalog.displaySequence(for: .resizePane(.right)), command: .resizePane(.right)),
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
