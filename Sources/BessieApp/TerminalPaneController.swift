import AppKit
import BessieCore
import Foundation
import GhosttyTerminal
import SwiftUI

@MainActor
final class TerminalControllerRegistry: ObservableObject {
    @Published private(set) var controllers: [String: PaneTerminalController] = [:]
    private var endpoint: HerdrTerminalEndpoint?

    func synchronize(visiblePaneIDs: Set<String>, endpoint: HerdrTerminalEndpoint) {
        if self.endpoint != endpoint {
            releaseAll()
            self.endpoint = endpoint
        }
        for paneID in visiblePaneIDs where controllers[paneID] == nil {
            controllers[paneID] = PaneTerminalController(paneID: paneID, endpoint: endpoint)
        }
        for paneID in Set(controllers.keys).subtracting(visiblePaneIDs) {
            controllers.removeValue(forKey: paneID)?.release()
        }
    }

    func releaseAll() {
        for controller in controllers.values { controller.release() }
        controllers.removeAll()
    }
}

@MainActor
final class PaneTerminalController: ObservableObject, Identifiable {
    let id: String
    let ghosttyController = TerminalController { builder in
        builder.withBackgroundOpacity(1)
    }
    let session: InMemoryTerminalSession
    let herdrController: HerdrTerminalController
    let inputRouter: TerminalInputRouter
    @Published private(set) var status: TerminalControllerStatus = .starting
    private let bridge: PaneTerminalBridge
    private var automationStarted = false

    init(paneID: String, endpoint: HerdrTerminalEndpoint) {
        id = paneID
        let bridge = PaneTerminalBridge()
        self.bridge = bridge
        let herdr = HerdrTerminalController(
            executablePath: endpoint.executablePath,
            paneID: paneID,
            socketPath: endpoint.socketPath,
            onFrame: { [weak bridge] bytes in bridge?.receive(bytes) },
            onState: { [weak bridge] state in bridge?.receive(state) }
        )
        herdrController = herdr
        inputRouter = TerminalInputRouter(transport: herdr)
        session = InMemoryTerminalSession(
            write: { [weak herdr] data in try? herdr?.sendRaw(data) },
            resize: { [weak herdr] viewport in
                herdr?.requestResize(
                    grid: TerminalGrid(columns: Int(viewport.columns), rows: Int(viewport.rows)),
                    cellWidthPixels: Int(viewport.cellWidthPixels),
                    cellHeightPixels: Int(viewport.cellHeightPixels)
                )
            }
        )
        bridge.session = session
        bridge.onState = { [weak self] state in self?.handle(state) }
        herdr.start()
    }

    func release() { herdrController.release() }
    func reconnectForVerification() { herdrController.reconnect(reason: "verification requested controller reconnect") }

    private func handle(_ state: TerminalControllerStatus) {
        status = state
        BessieDiagnosticLog.append("Terminal pane=\(id) state=\(state.diagnosticLabel)")
        guard case .ready = state,
              ProcessInfo.processInfo.environment["BESSIE_TERMINAL_LIVE_AUTOMATION"] == "1",
              !automationStarted
        else { return }
        automationStarted = true
        let token = id.replacingOccurrences(of: ":", with: "_")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            session.sendInput(Data("printf 'RAW_\(token)_牛é🐄'".utf8))
            try? inputRouter.send(.keys(["enter"]))
            try? inputRouter.send(.paste("printf 'PASTE_\(token)'"))
            try? inputRouter.send(.keys(["enter"]))
            BessieDiagnosticLog.append("Terminal pane=\(id) input=raw_unicode,special_enter,paste")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                let text = session.readViewportText() ?? ""
                let raw = text.contains("RAW_\(token)")
                let paste = text.contains("PASTE_\(token)")
                BessieDiagnosticLog.append("Terminal pane=\(id) viewport raw=\(raw) paste=\(paste) chars=\(text.count)")
                session.sendInput(Data("printf '\\n'; seq 1 80".utf8))
                try? inputRouter.send(.keys(["enter"]))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    try? inputRouter.send(.scroll(direction: .up, lines: 3, source: .wheel, column: nil, row: nil, modifiers: 0))
                    BessieDiagnosticLog.append("Terminal pane=\(id) input=scroll")
                }
            }
        }
    }

}

private final class PaneTerminalBridge: @unchecked Sendable {
    var session: InMemoryTerminalSession?
    var onState: (@MainActor (TerminalControllerStatus) -> Void)?

    func receive(_ bytes: Data) {
        session?.receive(bytes)
    }

    func receive(_ state: TerminalControllerStatus) {
        DispatchQueue.main.async { [weak self] in self?.onState?(state) }
    }
}

private extension TerminalControllerStatus {
    var diagnosticLabel: String {
        switch self {
        case .starting: "starting"
        case .waitingForFull: "waiting_full"
        case .ready(let grid, let sequence, let full): "ready_\(grid.columns)x\(grid.rows)_seq_\(sequence)_full_\(full)"
        case .reconnecting(let reason): "reconnecting_\(reason)"
        case .ownershipConflict: "ownership_conflict"
        case .stopped: "stopped"
        case .failed(let reason): "failed_\(reason)"
        }
    }
}

struct GhosttyPaneSurface: NSViewRepresentable {
    @ObservedObject var controller: PaneTerminalController
    let fontSize: Double

    func makeNSView(context: Context) -> BessieTerminalView {
        let view = BessieTerminalView(frame: .zero)
        view.controller = controller.ghosttyController
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(controller.session), fontSize: Float(fontSize))
        view.configuredFontSize = fontSize
        view.sendOperation = { [weak controller] operation in try? controller?.inputRouter.send(operation) }
        return view
    }

    func updateNSView(_ view: BessieTerminalView, context: Context) {
        if view.controller !== controller.ghosttyController { view.controller = controller.ghosttyController }
        if view.configuredFontSize != fontSize {
            view.configuration = TerminalSurfaceOptions(backend: .inMemory(controller.session), fontSize: Float(fontSize))
            view.configuredFontSize = fontSize
        }
        view.sendOperation = { [weak controller] operation in try? controller?.inputRouter.send(operation) }
        view.fitToSize()
    }
}

@MainActor
final class BessieTerminalView: TerminalView {
    var sendOperation: ((TerminalInputOperation) -> Void)?
    var configuredFontSize: Double = 13
    private var selecting = false

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 116 || event.keyCode == 121 {
            sendOperation?(.scroll(direction: event.keyCode == 116 ? .up : .down, lines: 1, source: .pageKey, column: nil, row: nil, modifiers: 0))
            return
        }
        if let combo = Self.herdrKeyCombo(event) {
            sendOperation?(.keys([combo]))
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" {
            if let text = NSPasteboard.general.string(forType: .string) { sendOperation?(.paste(text)) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let lines = max(1, Int(abs(delta) / 8))
        sendOperation?(.scroll(direction: delta > 0 ? .up : .down, lines: lines, source: .wheel, column: nil, row: nil, modifiers: 0))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selecting = event.modifierFlags.contains(.shift)
        if selecting { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) { if selecting { super.mouseDragged(with: event) } }
    override func mouseUp(with event: NSEvent) {
        if selecting { super.mouseUp(with: event) }
        selecting = false
    }

    private static func herdrKeyCombo(_ event: NSEvent) -> String? {
        let base: String?
        switch event.keyCode {
        case 123: base = "left"
        case 124: base = "right"
        case 125: base = "down"
        case 126: base = "up"
        case 36, 76: base = "enter"
        case 48: base = "tab"
        case 51: base = "backspace"
        case 53: base = "esc"
        case 122: base = "f1"
        case 120: base = "f2"
        case 99: base = "f3"
        case 118: base = "f4"
        case 96: base = "f5"
        case 97: base = "f6"
        case 98: base = "f7"
        case 100: base = "f8"
        case 101: base = "f9"
        case 109: base = "f10"
        case 103: base = "f11"
        case 111: base = "f12"
        default:
            if event.modifierFlags.contains(.control),
               let value = event.charactersIgnoringModifiers?.lowercased(), value.count == 1
            { base = value } else { base = nil }
        }
        guard let base else { return nil }
        var modifiers: [String] = []
        if event.modifierFlags.contains(.control) { modifiers.append("ctrl") }
        if event.modifierFlags.contains(.option) { modifiers.append("alt") }
        if event.modifierFlags.contains(.shift), base != "tab" { modifiers.append("shift") }
        if event.modifierFlags.contains(.shift), base == "tab" { return "shift+tab" }
        return (modifiers + [base]).joined(separator: "+")
    }
}
