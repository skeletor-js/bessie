import AppKit
import BessieCore
import SwiftUI

@MainActor
final class BessieKeyboardShortcutCoordinator: ObservableObject {
    private var monitor: Any?
    private var handler: ((BessieShortcutCommand) -> Void)?
    private var isZenActive: () -> Bool = { false }

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

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window?.sheetParent == nil else { return event }
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

struct BessieCommandPalette: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @StateObject private var keyRouting = BessieCommandPaletteKeyRouting()
    let close: () -> Void
    let entities: [CommandPaletteEntity]
    let noConnections: Bool
    let perform: (CommandPaletteRouteIntent) -> Void

    static let width: CGFloat = 560
    static let scrimOpacity = 0.28
    static let inputFontSize: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                BessieIconView(icon: .magnifyingGlass, size: 17)
                    .foregroundStyle(BessieDesign.subtle)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Self.inputFontSize))
                    .focused($searchFocused)
                    .accessibilityLabel("Search commands, panes, workspaces, Projects, and herds")
                Text("esc")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.subtle)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(BessieDesign.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle().fill(BessieDesign.border).frame(height: 1)

            if keyRouting.results.isEmpty {
                VStack(spacing: 8) {
                    BessieIconView(icon: .magnifyingGlass, size: 24)
                        .foregroundStyle(BessieDesign.faint)
                    Text(noConnections && query.isEmpty ? "No herds connected" : "No matching panes, workspaces, Projects, herds, or commands")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BessieDesign.subtle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(keyRouting.results.enumerated()), id: \.element.id) { index, item in
                                BessieCommandPaletteRow(item: item, selected: index == keyRouting.selection) {
                                    run(item.route)
                                }
                                .id(index)
                                .onHover { hovering in
                                    if hovering { keyRouting.selection = index }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: keyRouting.selection) { _, value in
                        if reduceMotion {
                            proxy.scrollTo(value, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
                        }
                    }
                }
            }

            Rectangle().fill(BessieDesign.border).frame(height: 1)
            HStack(spacing: 16) {
                Text("↑↓ move")
                Text("↵ open")
                Text("⌘↵ open in a new tab")
                Spacer()
                Text("panes · workspaces · projects · commands")
            }
            .font(.system(size: 11))
            .foregroundStyle(BessieDesign.faint)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .frame(width: Self.width)
        .frame(maxHeight: 520)
        .bessieSurface(base: BessieDesign.panel)
        .overlay {
            Rectangle().stroke(BessieDesign.borderStrong, lineWidth: 1)
        }
        .background(BessieWindowSnapshotProbe(role: "sheet"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
        .onAppear {
            keyRouting.onActivate = { run($0) }
            keyRouting.onDismiss = close
            let initialQuery = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "07" ? "sch" : ""
            query = initialQuery
            keyRouting.update(query: initialQuery, entities: entities)
            keyRouting.start()
        }
        .task {
            // Wait until SwiftUI has mounted the field before making it first responder.
            await Task.yield()
            guard !Task.isCancelled else { return }
            searchFocused = true
        }
        .onDisappear {
            keyRouting.stop()
        }
        .onChange(of: query) { _, newQuery in
            keyRouting.update(query: newQuery, entities: entities)
        }
        .onChange(of: entities) { _, newEntities in
            keyRouting.update(query: query, entities: newEntities)
        }
        .onKeyPress(.downArrow) {
            keyRouting.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            keyRouting.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard press.key == .return else { return .ignored }
            keyRouting.activate(alternate: press.modifiers.contains(.command))
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    private func run(_ route: CommandPaletteRouteIntent) {
        keyRouting.stop()
        close()
        DispatchQueue.main.async { perform(route) }
    }
}

/// Owns palette list selection + local key monitor so arrow keys work while the
/// search field is first responder (SwiftUI TextField otherwise swallows them).
@MainActor
final class BessieCommandPaletteKeyRouting: ObservableObject {
    @Published var selection = 0
    @Published private(set) var results: [CommandPaletteEntity] = []
    var onActivate: (CommandPaletteRouteIntent) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    private var monitor: Any?
    private var dispatchGate = CommandPaletteDispatchGate()

    func update(query: String, entities: [CommandPaletteEntity]) {
        let selectedID = results.indices.contains(selection) ? results[selection].id : nil
        let nextResults = CommandPaletteSearch().results(query: query, entities: entities)
        results = nextResults
        if let selectedID, let preservedIndex = nextResults.firstIndex(where: { $0.id == selectedID }) {
            selection = preservedIndex
        } else {
            selection = 0
        }
    }

    func moveSelection(by delta: Int) {
        selection = CommandPaletteKeyboard.movedSelection(
            current: selection,
            delta: delta,
            count: results.count
        )
    }

    func activate(alternate: Bool) {
        guard let route = takeActivationRoute(alternate: alternate) else { return }
        onActivate(route)
    }

    func start() {
        stop()
        dispatchGate = CommandPaletteDispatchGate()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let action = CommandPaletteKeyboard.action(
                keyCode: event.keyCode,
                command: flags.contains(.command),
                option: flags.contains(.option),
                control: flags.contains(.control),
                shift: flags.contains(.shift)
            )
            switch action {
            case .ignore:
                return event
            case .moveSelection(let delta):
                MainActor.assumeIsolated {
                    self.moveSelection(by: delta)
                }
                return nil
            case .activate(let alternate):
                let route = MainActor.assumeIsolated {
                    self.takeActivationRoute(alternate: alternate)
                }
                if let route {
                    DispatchQueue.main.async { self.onActivate(route) }
                }
                return nil
            case .dismiss:
                DispatchQueue.main.async { self.onDismiss() }
                return nil
            }
        }
    }

    private func takeActivationRoute(alternate: Bool) -> CommandPaletteRouteIntent? {
        guard results.indices.contains(selection) else { return nil }
        return dispatchGate.take(results[selection], alternate: alternate)
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct BessieCommandPaletteRow: View {
    let item: CommandPaletteEntity
    let selected: Bool
    let action: () -> Void

    private var state: AgentSemanticState {
        AgentSemanticState(herdrValue: item.state ?? "unknown")
    }

    private var icon: BessieIcon {
        switch item.kind {
        case .pane: .terminalWindow
        case .workspace: .squaresFour
        case .project: .stack
        case .connection: .hardDrives
        case .command: item.title.localizedCaseInsensitiveContains("split") ? .squareSplitHorizontal : .terminalWindow
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if item.state != nil {
                    BessieStatusGlyph(state: state)
                } else {
                    BessieIconView(icon: icon, size: 15)
                        .foregroundStyle(selected ? BessieDesign.accent : BessieDesign.subtle)
                }
                (Text(item.title).foregroundStyle(BessieDesign.strong)
                    + Text(item.detail.isEmpty ? "" : " · \(item.detail)").foregroundStyle(BessieDesign.subtle))
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text([item.location, item.shortcut].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                    .lineLimit(1)
                if item.kind == .pane {
                    BessieProviderMark(provider: item.keywords.first)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(selected ? BessieDesign.accentSoft : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(item.alternateRoute == nil ? "Open" : "Open, or press Command Return for the advertised alternate route")
    }

    private var accessibilityLabel: String {
        let status = item.state.map { ", \(HerdPresentationStatus(state: AgentSemanticState(herdrValue: $0)).rawValue)" } ?? ""
        let location = item.location.map { ", \($0)" } ?? ""
        return "\(item.kind.rawValue.capitalized): \(item.title)\(status), \(item.detail)\(location)"
    }
}
