import AppKit
import BessieCore
import SwiftUI

enum BessiePrefixAccessibilityAnnouncement: Equatable {
    case prefixEntered
    case resizeEntered
    case cancelled

    var message: String {
        switch self {
        case .prefixEntered: "Prefix command armed"
        case .resizeEntered: "Pane resize mode"
        case .cancelled: "Herdr keyboard mode cancelled"
        }
    }
}

struct BessiePrefixInputOwner: Equatable {
    let windowID: ObjectIdentifier
    let connectionID: String
    let connectionGeneration: UUID
    let paneID: String
    let terminalControllerID: ObjectIdentifier
    let terminalID: String

    init(
        window: NSWindow,
        connectionID: String,
        connectionGeneration: UUID,
        paneID: String,
        terminalControllerID: ObjectIdentifier,
        terminalID: String
    ) {
        windowID = ObjectIdentifier(window)
        self.connectionID = connectionID
        self.connectionGeneration = connectionGeneration
        self.paneID = paneID
        self.terminalControllerID = terminalControllerID
        self.terminalID = terminalID
    }
}

@MainActor
private func defaultPrefixInputOwner(
    window: NSWindow,
    terminal: BessieTerminalView
) -> BessiePrefixInputOwner {
    BessiePrefixInputOwner(
        window: window,
        connectionID: "",
        connectionGeneration: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
        paneID: terminal.paneID,
        terminalControllerID: ObjectIdentifier(terminal),
        terminalID: ""
    )
}

@MainActor
final class BessieKeyboardShortcutCoordinator: ObservableObject {
    enum PaletteEventPolicy: Equatable {
        case action(CommandPaletteKeyboard.Action)
        case buffer(String)
        case passThrough
        case consume
    }

    private struct PaletteRouting {
        let isSearchFocused: () -> Bool
        let bufferPrintableCharacters: (String) -> Void
        let handle: (CommandPaletteKeyboard.Action) -> Void
    }

    private var monitor: Any?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var handler: ((BessieShortcutCommand) -> Void)?
    private var prefixHandler: (HerdrPrefixCommand) -> Void = { _ in }
    private var sendLiteralPrefix: () -> Void = {}
    private var prefixOwner: @MainActor (NSWindow, BessieTerminalView) -> BessiePrefixInputOwner? = defaultPrefixInputOwner
    private var modeChanged: (HerdrPrefixMode) -> Void = { _ in }
    private var accessibilityAnnouncement: (BessiePrefixAccessibilityAnnouncement) -> Void = { _ in }
    private var isZenActive: () -> Bool = { false }
    private var paletteRouting: PaletteRouting?
    private var prefixReducer = HerdrPrefixReducer()
    private var armedOwner: BessiePrefixInputOwner?

    var prefixMode: HerdrPrefixMode { prefixReducer.mode }

    func start(
        isZenActive: @escaping () -> Bool = { false },
        handler: @escaping (BessieShortcutCommand) -> Void,
        prefixHandler: @escaping (HerdrPrefixCommand) -> Void = { _ in },
        sendLiteralPrefix: @escaping () -> Void = {},
        prefixOwner: @escaping @MainActor (NSWindow, BessieTerminalView) -> BessiePrefixInputOwner? = defaultPrefixInputOwner,
        modeChanged: @escaping (HerdrPrefixMode) -> Void = { _ in },
        accessibilityAnnouncement: @escaping (BessiePrefixAccessibilityAnnouncement) -> Void = { _ in }
    ) {
        self.isZenActive = isZenActive
        self.handler = handler
        self.prefixHandler = prefixHandler
        self.sendLiteralPrefix = sendLiteralPrefix
        self.prefixOwner = prefixOwner
        self.modeChanged = modeChanged
        self.accessibilityAnnouncement = accessibilityAnnouncement
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        installLifecycleObservers()
    }

    func update(
        isZenActive: @escaping () -> Bool = { false },
        handler: @escaping (BessieShortcutCommand) -> Void,
        prefixHandler: @escaping (HerdrPrefixCommand) -> Void = { _ in },
        sendLiteralPrefix: @escaping () -> Void = {},
        prefixOwner: @escaping @MainActor (NSWindow, BessieTerminalView) -> BessiePrefixInputOwner? = defaultPrefixInputOwner,
        modeChanged: @escaping (HerdrPrefixMode) -> Void = { _ in },
        accessibilityAnnouncement: @escaping (BessiePrefixAccessibilityAnnouncement) -> Void = { _ in }
    ) {
        self.isZenActive = isZenActive
        self.handler = handler
        self.prefixHandler = prefixHandler
        self.sendLiteralPrefix = sendLiteralPrefix
        self.prefixOwner = prefixOwner
        self.modeChanged = modeChanged
        self.accessibilityAnnouncement = accessibilityAnnouncement
    }

    func enterCommandPalette(
        isSearchFocused: @escaping () -> Bool,
        bufferPrintableCharacters: @escaping (String) -> Void,
        handle: @escaping (CommandPaletteKeyboard.Action) -> Void
    ) {
        paletteRouting = PaletteRouting(
            isSearchFocused: isSearchFocused,
            bufferPrintableCharacters: bufferPrintableCharacters,
            handle: handle
        )
        cancelPrefixSequence()
    }

    func exitCommandPalette() {
        paletteRouting = nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers.removeAll()
        monitor = nil
        cancelPrefixSequence()
        handler = nil
        prefixHandler = { _ in }
        sendLiteralPrefix = {}
        prefixOwner = defaultPrefixInputOwner
        modeChanged = { _ in }
        accessibilityAnnouncement = { _ in }
        paletteRouting = nil
    }

    func cancelPrefixSequence() {
        let priorMode = prefixReducer.mode
        prefixReducer.cancel()
        armedOwner = nil
        if priorMode != .idle {
            modeChanged(.idle)
            accessibilityAnnouncement(.cancelled)
        }
    }

    func reconcilePrefixOwner(_ currentOwner: BessiePrefixInputOwner?) {
        guard prefixReducer.mode != .idle, currentOwner != armedOwner else { return }
        cancelPrefixSequence()
    }

    func handle(_ event: NSEvent, in windowOverride: NSWindow? = nil) -> NSEvent? {
        let window = windowOverride ?? event.window
        let firstResponder = window?.firstResponder
        let terminal = firstResponder as? BessieTerminalView
        let hasMarkedText = (firstResponder as? any NSTextInputClient)?.hasMarkedText() ?? false
        let canRoutePrefix = Self.shouldRoutePrefix(
            mainWindow: window?.identifier == BessieWindowCoordinator.mainWindowIdentifier,
            hasAttachedSheet: window?.attachedSheet != nil || window?.sheetParent != nil,
            paletteActive: paletteRouting != nil,
            firstResponderIsTerminal: terminal != nil,
            firstResponderIsEditableText: Self.isEditableTextResponder(firstResponder),
            hasMarkedText: hasMarkedText
        )
        let currentOwner: BessiePrefixInputOwner? = if let window, let terminal {
            prefixOwner(window, terminal)
        } else {
            nil
        }
        let commandModifiedWhileArmed = prefixReducer.mode != .idle
            && event.type == .keyDown
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if prefixReducer.mode != .idle, currentOwner != armedOwner {
            reconcilePrefixOwner(currentOwner)
        } else if commandModifiedWhileArmed {
            let policy = BessieKeyboardShortcutRouter.policy(for: Self.stroke(for: event))
            cancelPrefixSequence()
            switch policy {
            case .terminalShortcut:
                // Retained terminal conveniences continue through the existing
                // Bessie/libghostty responder policy after cancelling prefix mode.
                break
            case .appCommand(let command):
                guard !Self.hasAppKitCommandEquivalent(command) else { return event }
                // Some Bessie-owned native chords are intentionally coordinator-
                // only because they have no AppKit menu item.
                handler?(command)
                return nil
            case .passthrough:
                // Native application/menu equivalents remain AppKit-owned.
                return event
            }
        } else if canRoutePrefix, currentOwner != nil {
            let priorMode = prefixReducer.mode
            let outcome = prefixReducer.handle(Self.stroke(for: event))
            if priorMode == .idle, prefixReducer.mode != .idle {
                armedOwner = currentOwner
            } else if prefixReducer.mode == .idle {
                armedOwner = nil
            }
            if prefixReducer.mode != priorMode {
                modeChanged(prefixReducer.mode)
                if priorMode == .idle, prefixReducer.mode == .armed {
                    accessibilityAnnouncement(.prefixEntered)
                } else if prefixReducer.mode == .resize {
                    accessibilityAnnouncement(.resizeEntered)
                } else if prefixReducer.mode == .idle, Self.stroke(for: event).key == .escape {
                    accessibilityAnnouncement(.cancelled)
                }
            }
            switch outcome {
            case .passThrough:
                break
            case .consume:
                return nil
            case .enterResize:
                prefixHandler(.enterResize)
                return nil
            case .execute(let command):
                prefixHandler(command)
                return nil
            case .sendLiteralPrefix:
                sendLiteralPrefix()
                return nil
            }
        } else if prefixReducer.mode != .idle {
            cancelPrefixSequence()
        }

        guard event.type == .keyDown else { return event }
        guard window?.sheetParent == nil else { return event }
        if let paletteRouting {
            guard window?.identifier == BessieWindowCoordinator.mainWindowIdentifier else { return event }
            return routePaletteEvent(event, routing: paletteRouting)
        }
        if Self.shouldExitZen(keyCode: event.keyCode, isZenActive: isZenActive()) {
            handler?(.exitZen)
            return nil
        }
        switch BessieKeyboardShortcutRouter.policy(for: Self.stroke(for: event)) {
        case .passthrough:
            return event
        case .appCommand(let command):
            // Product chords are window-scoped and identical whether focus is the
            // terminal, rail, or chrome. Only real text editing / IME composition
            // keeps ownership of the keystroke (AE4 modal/text protection).
            guard Self.shouldRoute(
                command,
                hasMarkedText: hasMarkedText,
                firstResponderIsEditableText: Self.isEditableTextResponder(firstResponder)
            ) else {
                return event
            }
            handler?(command)
            return nil
        case .terminalShortcut(let action):
            // Terminal-only mappings (copy/paste/clear/select) still require
            // the focused terminal surface so they never steal from text fields.
            guard let terminal = window?.firstResponder as? BessieTerminalView,
                  terminal.performBessieShortcut(action)
            else { return event }
            return nil
        }
    }

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPrefixSequence() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPrefixSequence() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: NSWindow.willBeginSheetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPrefixSequence() }
        })
    }

    private func routePaletteEvent(_ event: NSEvent, routing: PaletteRouting) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let firstResponder = event.window?.firstResponder
        let hasMarkedText = (firstResponder as? any NSTextInputClient)?.hasMarkedText() ?? false
        let searchHasFocus = routing.isSearchFocused() && Self.isEditableTextResponder(firstResponder)
        let unmodified = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let pasteboardText = flags.contains(.command) && unmodified == "v"
            ? NSPasteboard.general.string(forType: .string)
            : nil
        let policy = Self.paletteEventPolicy(
            keyCode: event.keyCode,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift),
            hasMarkedText: hasMarkedText,
            isSearchFocused: searchHasFocus,
            pasteboardText: pasteboardText
        )
        switch policy {
        case .action(let action):
            routing.handle(action)
            return nil
        case .buffer(let characters):
            routing.bufferPrintableCharacters(characters)
            return nil
        case .passThrough:
            return event
        case .consume:
            return nil
        }
    }

    static func paletteEventPolicy(
        keyCode: UInt16,
        characters: String?,
        charactersIgnoringModifiers: String?,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool,
        hasMarkedText: Bool,
        isSearchFocused: Bool,
        pasteboardText: String?
    ) -> PaletteEventPolicy {
        if hasMarkedText, !command {
            return .passThrough
        }

        let unmodified = charactersIgnoringModifiers?.lowercased() ?? ""
        if command, shift, !option, !control, unmodified == "p" {
            return .action(.dismiss)
        }

        let action = CommandPaletteKeyboard.action(
            keyCode: keyCode,
            command: command,
            option: option,
            control: control,
            shift: shift
        )
        if action != .ignore { return .action(action) }

        if command {
            guard !option, !control, !shift else { return .consume }
            if ["q", "h", "m"].contains(unmodified) { return .passThrough }
            if ["a", "c", "v", "x", "z"].contains(unmodified) {
                if isSearchFocused { return .passThrough }
                if unmodified == "v", let pasteboardText, !pasteboardText.isEmpty {
                    return .buffer(pasteboardText)
                }
            }
            return .consume
        }
        if control { return .consume }

        if let characters,
           !characters.isEmpty,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            return isSearchFocused ? .passThrough : .buffer(characters)
        }

        // Once focused, the TextField keeps ordinary editing/navigation keys.
        // Before focus they are consumed so no background control can react.
        return isSearchFocused ? .passThrough : .consume
    }

    /// App/product shortcuts use one policy everywhere in the main window.
    /// They do not require terminal first-responder. They yield only for IME
    /// composition and ordinary editable text controls (not the terminal).
    static func shouldRoute(
        _ command: BessieShortcutCommand,
        hasMarkedText: Bool,
        firstResponderIsEditableText: Bool
    ) -> Bool {
        guard !hasMarkedText else { return false }
        if firstResponderIsEditableText {
            return allowsDuringTextEditing(command)
        }
        return true
    }

    /// Back-compat overload used by older tests/call sites. Terminal focus no
    /// longer gates product shortcuts; only `hasMarkedText` is honored here.
    static func shouldRoute(
        _ command: BessieShortcutCommand,
        firstResponderIsTerminal: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        _ = firstResponderIsTerminal
        return shouldRoute(
            command,
            hasMarkedText: hasMarkedText,
            firstResponderIsEditableText: false
        )
    }

    static func shouldExitZen(keyCode: UInt16, isZenActive: Bool) -> Bool {
        isZenActive && keyCode == 53
    }

    private static func hasAppKitCommandEquivalent(_ command: BessieShortcutCommand) -> Bool {
        switch command {
        case .showCommandPalette, .showSettings, .toggleZen,
             .previousAgent, .nextAgent, .openNextNeedsYou:
            true
        default:
            false
        }
    }

    static func shouldRoutePrefix(
        mainWindow: Bool,
        hasAttachedSheet: Bool,
        paletteActive: Bool,
        firstResponderIsTerminal: Bool,
        firstResponderIsEditableText: Bool,
        hasMarkedText: Bool
    ) -> Bool {
        mainWindow
            && !hasAttachedSheet
            && !paletteActive
            && firstResponderIsTerminal
            && !firstResponderIsEditableText
            && !hasMarkedText
    }

    /// True when the first responder is an ordinary AppKit/SwiftUI text editor
    /// that should keep Option-letter and non-global chords for typing.
    static func isEditableTextResponder(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        // Terminal surfaces implement text-input protocols for IME; they are not
        // "typing in a form field" and must not suppress product chords.
        if responder is BessieTerminalView { return false }
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEditable
        }
        return false
    }

    /// Commands that remain available while a text field is focused.
    /// Everything else yields so typing/selection is not hijacked (AE4).
    static func allowsDuringTextEditing(_ command: BessieShortcutCommand) -> Bool {
        switch command {
        case .showCommandPalette, .showSettings, .toggleZen, .exitZen,
             .openNextNeedsYou, .previousAgent, .nextAgent:
            return true
        default:
            return false
        }
    }

    /// Deprecated product-gate: topology chords used to require terminal first
    /// responder. Always false now — product shortcuts share one window policy.
    static func requiresWorkspaceTerminalResponder(_ command: BessieShortcutCommand) -> Bool {
        _ = command
        return false
    }

    /// True when typing in a text field should keep this command (yield to text).
    static func blocksDuringTextEditing(_ command: BessieShortcutCommand) -> Bool {
        return !allowsDuringTextEditing(command)
    }

    static func stroke(for event: NSEvent) -> BessieShortcutStroke {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key: BessieShortcutKey
        let phase: BessieShortcutEventPhase
        switch event.type {
        case .keyUp: phase = .keyUp
        case .flagsChanged: phase = .modifierOnly
        default: phase = .keyDown
        }
        switch (phase, event.keyCode) {
        case (.modifierOnly, _): key = .character("")
        case (_, 123): key = .leftArrow
        case (_, 124): key = .rightArrow
        case (_, 125): key = .downArrow
        case (_, 126): key = .upArrow
        case (_, 53): key = .escape
        case (_, 48): key = flags.contains(.shift) ? .backtab : .tab
        case (_, 36), (_, 76): key = .enter
        case (_, 51): key = .backspace
        case (_, 117): key = .forwardDelete
        case (_, 115): key = .home
        case (_, 119): key = .end
        case (_, 116): key = .pageUp
        case (_, 121): key = .pageDown
        case (_, 122): key = .function(1)
        case (_, 120): key = .function(2)
        case (_, 99): key = .function(3)
        case (_, 118): key = .function(4)
        case (_, 96): key = .function(5)
        case (_, 97): key = .function(6)
        case (_, 98): key = .function(7)
        case (_, 100): key = .function(8)
        case (_, 101): key = .function(9)
        case (_, 109): key = .function(10)
        case (_, 103): key = .function(11)
        case (_, 111): key = .function(12)
        case (_, 27): key = .minus
        case (_, 78): key = .keypadMinus
        default: key = .character(event.charactersIgnoringModifiers ?? "")
        }
        return BessieShortcutStroke(
            key: key,
            control: flags.contains(.control),
            option: flags.contains(.option),
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            layoutCharacter: phase == .modifierOnly ? nil : event.characters,
            phase: phase,
            isRepeat: phase == .keyDown && event.isARepeat
        )
    }
}
