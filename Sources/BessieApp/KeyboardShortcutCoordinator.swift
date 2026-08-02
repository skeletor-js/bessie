import AppKit
import BessieCore
import SwiftUI

@MainActor
final class BessieKeyboardShortcutCoordinator: ObservableObject {
    private let router = BessieKeyboardShortcutRouter()
    private var monitor: Any?
    private var handler: ((BessieShortcutCommand) -> Void)?

    func start(handler: @escaping (BessieShortcutCommand) -> Void) {
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func update(handler: @escaping (BessieShortcutCommand) -> Void) {
        self.handler = handler
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window?.sheetParent == nil else { return event }
        switch router.handle(Self.stroke(for: event)) {
        case .passthrough:
            return event
        case .command(let command):
            handler?(command)
            return nil
        }
    }

    private static func stroke(for event: NSEvent) -> BessieShortcutStroke {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key: BessieShortcutKey
        switch event.keyCode {
        case 123: key = .leftArrow
        case 124: key = .rightArrow
        case 125: key = .downArrow
        case 126: key = .upArrow
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
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var selection = 0
    let close: () -> Void
    let perform: (BessieShortcutCommand) -> Void

    private var commands: [BessieCommandDefinition] {
        BessieKeyboardShortcutRouter.commands.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "command")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(BessieDesign.strong)
                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .medium))
                    .focused($searchFocused)
                Text("⌘B")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(BessieDesign.subtle)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(BessieDesign.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            Rectangle().fill(BessieDesign.border).frame(height: 1)

            if commands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(BessieDesign.faint)
                    Text("No matching commands")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BessieDesign.subtle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(commands.enumerated()), id: \.offset) { index, item in
                                Button {
                                    run(item.command)
                                } label: {
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(index == selection ? BessieDesign.strong : BessieDesign.text)
                                            Text(item.detail)
                                                .font(.system(size: 11))
                                                .foregroundStyle(index == selection ? BessieDesign.text : BessieDesign.subtle)
                                        }
                                        Spacer(minLength: 16)
                                        if let shortcut = item.shortcut {
                                            Text(shortcut)
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                .foregroundStyle(index == selection ? BessieDesign.strong : BessieDesign.subtle)
                                        }
                                    }
                                    .padding(.horizontal, 13)
                                    .frame(height: 52)
                                    .background(index == selection ? BessieDesign.selected : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay {
                                        if index == selection {
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(BessieDesign.borderStrong, lineWidth: 1)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(index)
                                .onHover { hovering in if hovering { selection = index } }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                    }
                    .onChange(of: selection) { _, value in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(value, anchor: .center) }
                    }
                }
            }

            Rectangle().fill(BessieDesign.border).frame(height: 1)
            HStack(spacing: 14) {
                Text("↑↓ Navigate")
                Text("↵ Run")
                Text("Esc Close")
                Spacer()
                Text("Commands act in Bessie or through Herdr")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(BessieDesign.subtle)
            .padding(.horizontal, 18)
            .frame(height: 34)
        }
        .frame(width: 640, height: 520)
        .background(BessieCowprintTexture(base: BessieDesign.panel, crop: .workspace, intensityScale: 0.22))
        .overlay {
            Rectangle().stroke(BessieDesign.borderStrong, lineWidth: 1)
        }
        .background(BessieWindowSnapshotProbe(role: "sheet"))
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onKeyPress(.downArrow) {
            guard !commands.isEmpty else { return .handled }
            selection = min(selection + 1, commands.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            guard commands.indices.contains(selection) else { return .handled }
            run(commands[selection].command)
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
    }

    private func run(_ command: BessieShortcutCommand) {
        close()
        DispatchQueue.main.async { perform(command) }
    }
}
