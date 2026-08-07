import AppKit
import BessieCore
import SwiftUI

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
    private var handler: ((BessieShortcutCommand) -> Void)?
    private var isZenActive: () -> Bool = { false }
    private var paletteRouting: PaletteRouting?

    func start(isZenActive: @escaping () -> Bool = { false }, handler: @escaping (BessieShortcutCommand) -> Void) {
        self.isZenActive = isZenActive
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func update(isZenActive: @escaping () -> Bool = { false }, handler: @escaping (BessieShortcutCommand) -> Void) {
        self.isZenActive = isZenActive
        self.handler = handler
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
    }

    func exitCommandPalette() {
        paletteRouting = nil
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
        paletteRouting = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window?.sheetParent == nil else { return event }
        if let paletteRouting {
            guard event.window?.identifier == BessieWindowCoordinator.mainWindowIdentifier else { return event }
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
            let firstResponder = event.window?.firstResponder
            let hasMarkedText = (firstResponder as? any NSTextInputClient)?.hasMarkedText() ?? false
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
            // Terminal-only mappings (copy/paste/0x02/clear/select) still require
            // the focused terminal surface so they never steal from text fields.
            guard let terminal = event.window?.firstResponder as? BessieTerminalView,
                  terminal.performBessieShortcut(action)
            else { return event }
            return nil
        }
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
        switch event.keyCode {
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
        case 51: key = .backspace
        case 117: key = .forwardDelete
        default: key = .character(event.charactersIgnoringModifiers ?? "")
        }
        return BessieShortcutStroke(
            key: key,
            control: flags.contains(.control),
            option: flags.contains(.option),
            command: flags.contains(.command),
            shift: flags.contains(.shift)
        )
    }
}
