import Foundation

public struct HerdrPrefixRuntimeIdentity: Equatable, Sendable {
    public let herdrVersion: String
    public let protocolVersion: Int
    public let sourceRevision: String

    public init(herdrVersion: String, protocolVersion: Int, sourceRevision: String) {
        self.herdrVersion = herdrVersion
        self.protocolVersion = protocolVersion
        self.sourceRevision = sourceRevision
    }
}

public enum HerdrPrefixPaneCycleDirection: Equatable, Sendable {
    case previous
    case next
}

public enum HerdrPrefixCommand: Equatable, Sendable {
    case newTab
    case nextTab
    case previousTab
    case focusTab(Int)
    case renameTab
    case closeTab
    case splitPane(SplitDirection)
    case focusPane(PaneDirection)
    case swapPane(PaneDirection)
    case cyclePane(HerdrPrefixPaneCycleDirection)
    case closePane
    case toggleZoom
    case enterResize
    case resizePane(PaneDirection)
    case renamePane
    case newWorkspace
    case renameWorkspace
    case closeWorkspace
    case showKeyboardReference
    case showWorkspacePicker
    case showCommandPalette
    case quitBessie
    case toggleSidebar
}

public enum HerdrPrefixBindingAvailability: Equatable, Sendable {
    case supported(HerdrPrefixCommand)
    case graphicalEquivalent(HerdrPrefixCommand)
    case unavailable(String)
}

public struct HerdrPrefixCommandDefinition: Equatable, Sendable {
    public let normalizedBinding: String
    public let displaySequence: String
    public let title: String
    public let availability: HerdrPrefixBindingAvailability

    public init(
        normalizedBinding: String,
        title: String,
        availability: HerdrPrefixBindingAvailability
    ) {
        self.normalizedBinding = normalizedBinding
        displaySequence = "Ctrl-B \(Self.displayRHS(normalizedBinding))"
        self.title = title
        self.availability = availability
    }

    private static func displayRHS(_ binding: String) -> String {
        if binding.hasPrefix("shift+") && binding != "shift+tab" {
            return "Shift-\(binding.dropFirst("shift+".count).uppercased())"
        }
        switch binding {
        case "shift+tab": return "Shift-Tab"
        case "tab": return "Tab"
        default:
            return binding
        }
    }
}

public enum HerdrPrefixCommandCatalog {
    public static let runtimeIdentity = HerdrPrefixRuntimeIdentity(
        herdrVersion: "0.8.0",
        protocolVersion: 19,
        sourceRevision: "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
    )

    public static let definitions: [HerdrPrefixCommandDefinition] = [
        definition("c", "New tab", .supported(.newTab)),
        definition("n", "Next tab", .supported(.nextTab)),
        definition("p", "Previous tab", .supported(.previousTab)),
        definition("1", "Focus tab 1", .supported(.focusTab(1))),
        definition("2", "Focus tab 2", .supported(.focusTab(2))),
        definition("3", "Focus tab 3", .supported(.focusTab(3))),
        definition("4", "Focus tab 4", .supported(.focusTab(4))),
        definition("5", "Focus tab 5", .supported(.focusTab(5))),
        definition("6", "Focus tab 6", .supported(.focusTab(6))),
        definition("7", "Focus tab 7", .supported(.focusTab(7))),
        definition("8", "Focus tab 8", .supported(.focusTab(8))),
        definition("9", "Focus tab 9", .supported(.focusTab(9))),
        definition("shift+t", "Rename tab", .supported(.renameTab)),
        definition("shift+x", "Close tab", .supported(.closeTab)),
        definition("v", "Split pane right", .supported(.splitPane(.right))),
        definition("-", "Split pane down", .supported(.splitPane(.down))),
        definition("h", "Focus pane left", .supported(.focusPane(.left))),
        definition("j", "Focus pane down", .supported(.focusPane(.down))),
        definition("k", "Focus pane up", .supported(.focusPane(.up))),
        definition("l", "Focus pane right", .supported(.focusPane(.right))),
        definition("shift+h", "Swap pane left", .supported(.swapPane(.left))),
        definition("shift+j", "Swap pane down", .supported(.swapPane(.down))),
        definition("shift+k", "Swap pane up", .supported(.swapPane(.up))),
        definition("shift+l", "Swap pane right", .supported(.swapPane(.right))),
        definition("tab", "Next pane", .supported(.cyclePane(.next))),
        definition("shift+tab", "Previous pane", .supported(.cyclePane(.previous))),
        definition("x", "Close pane", .supported(.closePane)),
        definition("z", "Toggle pane zoom", .supported(.toggleZoom)),
        definition("r", "Resize pane", .supported(.enterResize)),
        definition("shift+p", "Rename pane", .supported(.renamePane)),
        definition("shift+n", "New workspace", .supported(.newWorkspace)),
        definition("shift+w", "Rename workspace", .supported(.renameWorkspace)),
        definition("shift+d", "Close workspace", .supported(.closeWorkspace)),
        definition("?", "Keyboard reference", .graphicalEquivalent(.showKeyboardReference)),
        definition("w", "Open Workspaces", .graphicalEquivalent(.showWorkspacePicker)),
        definition("g", "Open command palette", .graphicalEquivalent(.showCommandPalette)),
        definition("q", "Quit Bessie", .graphicalEquivalent(.quitBessie)),
        definition("b", "Toggle sidebar", .graphicalEquivalent(.toggleSidebar)),
        definition("[", "Copy mode", .unavailable("Real Herdr copy mode is unavailable through protocol 19.")),
        definition("e", "Edit scrollback", .unavailable("Herdr scrollback editor mode is unavailable through protocol 19.")),
        definition("s", "Herdr settings", .unavailable("Herdr Settings mode is unavailable through protocol 19.")),
        definition("o", "Open notification target", .unavailable("Herdr notification-target routing is unavailable through protocol 19.")),
        definition("shift+r", "Reload Herdr configuration", .unavailable("Herdr's effective keymap cannot be refreshed or discovered through protocol 19.")),
        definition("shift+g", "Create worktree", .unavailable("Worktrees are outside Bessie V1 scope.")),
    ]

    static let definitionByBinding = Dictionary(
        uniqueKeysWithValues: definitions.map { ($0.normalizedBinding, $0) }
    )

    public static func displaySequence(for command: HerdrPrefixCommand) -> String? {
        if case .resizePane(let direction) = command {
            guard let prefix = displaySequence(for: .enterResize) else { return nil }
            return "\(prefix) \(resizeBinding(direction))"
        }
        return definitions.first { definition in
            switch definition.availability {
            case .supported(let candidate), .graphicalEquivalent(let candidate):
                return candidate == command
            case .unavailable:
                return false
            }
        }?.displaySequence
    }

    private static func definition(
        _ binding: String,
        _ title: String,
        _ availability: HerdrPrefixBindingAvailability
    ) -> HerdrPrefixCommandDefinition {
        HerdrPrefixCommandDefinition(
            normalizedBinding: binding,
            title: title,
            availability: availability
        )
    }

    private static func resizeBinding(_ direction: PaneDirection) -> String {
        switch direction {
        case .left: "h"
        case .down: "j"
        case .up: "k"
        case .right: "l"
        }
    }
}

public enum HerdrPrefixMode: Equatable, Sendable {
    case idle
    case armed
    case resize
}

public enum HerdrPrefixReducerOutcome: Equatable, Sendable {
    case passThrough
    case consume
    case execute(HerdrPrefixCommand)
    case enterResize
    case sendLiteralPrefix
}

public struct HerdrPrefixReducer: Equatable, Sendable {
    public private(set) var mode: HerdrPrefixMode = .idle
    private var suppressedRepeatBinding: String?

    public init() {}

    public mutating func handle(_ stroke: BessieShortcutStroke) -> HerdrPrefixReducerOutcome {
        switch stroke.phase {
        case .keyUp:
            if suppressedRepeatBinding == Self.repeatIdentity(for: stroke) {
                suppressedRepeatBinding = nil
            }
            return .passThrough
        case .modifierOnly:
            return mode == .idle ? .passThrough : .consume
        case .keyDown:
            break
        }

        switch mode {
        case .idle:
            return handleIdle(stroke)
        case .armed:
            return handleArmed(stroke)
        case .resize:
            return handleResize(stroke)
        }
    }

    public mutating func cancel() {
        mode = .idle
        suppressedRepeatBinding = nil
    }

    private mutating func handleIdle(_ stroke: BessieShortcutStroke) -> HerdrPrefixReducerOutcome {
        let identity = Self.repeatIdentity(for: stroke)
        if stroke.isRepeat,
           Self.isPrefix(stroke) || identity == suppressedRepeatBinding {
            return .consume
        }
        if !stroke.isRepeat { suppressedRepeatBinding = nil }
        guard Self.isPrefix(stroke) else { return .passThrough }
        mode = .armed
        return .consume
    }

    private mutating func handleArmed(_ stroke: BessieShortcutStroke) -> HerdrPrefixReducerOutcome {
        if stroke.isRepeat { return .consume }
        if Self.isPrefix(stroke) {
            mode = .idle
            suppressedRepeatBinding = Self.repeatIdentity(for: stroke)
            return .sendLiteralPrefix
        }
        if stroke.key == .escape {
            return consumeAndDisarm(stroke)
        }
        guard let binding = Self.normalizedBinding(for: stroke),
              let definition = HerdrPrefixCommandCatalog.definitionByBinding[binding]
        else {
            return consumeAndDisarm(stroke)
        }

        suppressedRepeatBinding = binding
        switch definition.availability {
        case .supported(.enterResize):
            mode = .resize
            return .enterResize
        case .supported(let command), .graphicalEquivalent(let command):
            mode = .idle
            return .execute(command)
        case .unavailable:
            mode = .idle
            return .consume
        }
    }

    private mutating func handleResize(_ stroke: BessieShortcutStroke) -> HerdrPrefixReducerOutcome {
        let identity = Self.repeatIdentity(for: stroke)
        if stroke.isRepeat, identity == suppressedRepeatBinding {
            return .consume
        }
        if Self.isResizeExit(stroke) {
            mode = .idle
            suppressedRepeatBinding = identity
            return .consume
        }
        if let direction = Self.resizeDirection(for: stroke) {
            suppressedRepeatBinding = nil
            return .execute(.resizePane(direction))
        }
        return .consume
    }

    private mutating func consumeAndDisarm(
        _ stroke: BessieShortcutStroke
    ) -> HerdrPrefixReducerOutcome {
        mode = .idle
        suppressedRepeatBinding = Self.repeatIdentity(for: stroke)
        return .consume
    }

    private static func isPrefix(_ stroke: BessieShortcutStroke) -> Bool {
        guard stroke.control, !stroke.option, !stroke.command, !stroke.shift,
              case .character(let raw) = stroke.key
        else { return false }
        return raw.lowercased() == "b"
    }

    private static func isResizeExit(_ stroke: BessieShortcutStroke) -> Bool {
        guard !stroke.control, !stroke.option, !stroke.command, !stroke.shift else { return false }
        switch stroke.key {
        case .escape, .enter:
            return true
        case .character(let raw):
            return raw.lowercased() == "r"
        default:
            return false
        }
    }

    private static func resizeDirection(for stroke: BessieShortcutStroke) -> PaneDirection? {
        guard !stroke.control, !stroke.option, !stroke.command, !stroke.shift else { return nil }
        switch stroke.key {
        case .leftArrow: return .left
        case .downArrow: return .down
        case .upArrow: return .up
        case .rightArrow: return .right
        case .character(let raw):
            switch raw.lowercased() {
            case "h": return .left
            case "j": return .down
            case "k": return .up
            case "l": return .right
            default: return nil
            }
        default:
            return nil
        }
    }

    private static func normalizedBinding(for stroke: BessieShortcutStroke) -> String? {
        guard !stroke.control, !stroke.option, !stroke.command else { return nil }
        switch stroke.key {
        case .tab, .backtab:
            return stroke.shift || stroke.key == .backtab ? "shift+tab" : "tab"
        case .minus, .keypadMinus:
            return stroke.shift ? nil : "-"
        case .character(let raw):
            if let produced = stroke.layoutCharacter,
               produced.count == 1,
               produced == "?" {
                return "?"
            }
            let key = raw.lowercased()
            guard key.count == 1, !key.isEmpty else { return nil }
            return stroke.shift ? "shift+\(key)" : key
        default:
            return nil
        }
    }

    private static func repeatIdentity(for stroke: BessieShortcutStroke) -> String {
        if isPrefix(stroke) { return "ctrl+b" }
        if let binding = normalizedBinding(for: stroke) { return binding }
        return String(describing: stroke.key)
    }
}

public struct HerdrResizePendingQueue: Equatable, Sendable {
    public static let capacity = 32
    private var pending: [PaneDirection] = []

    public init() {}

    public var count: Int { pending.count }
    public var isEmpty: Bool { pending.isEmpty }

    @discardableResult
    public mutating func enqueue(_ direction: PaneDirection) -> Bool {
        guard pending.count < Self.capacity else { return false }
        pending.append(direction)
        return true
    }

    public mutating func dequeue() -> PaneDirection? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    public mutating func clear() {
        pending.removeAll(keepingCapacity: true)
    }
}

public struct HerdrResizeDispatchStep: Equatable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let paneID: String
    public let direction: PaneDirection
}

public struct HerdrResizeDispatchRun<Owner: Equatable> {
    public let id: UUID
    public let owner: Owner
    public private(set) var targetPaneID: String?
    public var pendingCount: Int { pending.count }

    private var pending = HerdrResizePendingQueue()
    private var inFlightStepID: UUID?

    public init(owner: Owner, id: UUID = UUID()) {
        self.id = id
        self.owner = owner
    }

    @discardableResult
    public mutating func enqueue(_ direction: PaneDirection) -> Bool {
        pending.enqueue(direction)
    }

    @discardableResult
    public mutating func activate(targetPaneID: String, currentOwner: Owner) -> Bool {
        guard currentOwner == owner else { return false }
        self.targetPaneID = targetPaneID
        return true
    }

    public mutating func nextStep(currentOwner: Owner) -> HerdrResizeDispatchStep? {
        guard currentOwner == owner,
              inFlightStepID == nil,
              let targetPaneID,
              let direction = pending.dequeue()
        else { return nil }
        let step = HerdrResizeDispatchStep(
            id: UUID(),
            runID: id,
            paneID: targetPaneID,
            direction: direction
        )
        inFlightStepID = step.id
        return step
    }

    @discardableResult
    public mutating func complete(
        _ step: HerdrResizeDispatchStep,
        currentOwner: Owner,
        targetStillExists: Bool
    ) -> Bool {
        guard step.runID == id, inFlightStepID == step.id else { return false }
        inFlightStepID = nil
        return currentOwner == owner && targetStillExists && step.paneID == targetPaneID
    }

    @discardableResult
    public mutating func fail(_ step: HerdrResizeDispatchStep) -> Bool {
        guard step.runID == id, inFlightStepID == step.id else { return false }
        inFlightStepID = nil
        pending.clear()
        return true
    }

    public mutating func cancel() {
        targetPaneID = nil
        inFlightStepID = nil
        pending.clear()
    }
}
