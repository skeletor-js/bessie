import AppKit
import SwiftUI

@MainActor
protocol BessieWindowRouting: AnyObject {
    func showOrCreateMainWindow()
    func showSettings()
}

@MainActor
protocol BessieMainWindowPresenting: AnyObject {
    var isMiniaturized: Bool { get }
    func deminiaturize(_ sender: Any?)
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: BessieMainWindowPresenting {}

struct BessieMainWindowProbe: NSViewRepresentable {
    let coordinator: BessieWindowCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { coordinator.registerMainWindow(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { coordinator.registerMainWindow(window) }
        }
    }
}

@MainActor
final class BessieWindowCoordinator: BessieWindowRouting {
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier(BessieWindowChromePolicy.mainWindowIdentifier)

    private let application: NSApplication
    private var openWindow: (() -> Void)?
    private var openSettings: (() -> Void)?
    private var creationPending = false
    private weak var registeredMainWindow: (any BessieMainWindowPresenting)?

    init(application: NSApplication = .shared) {
        self.application = application
    }

    func install(openWindow: @escaping () -> Void, openSettings: @escaping () -> Void = {}) {
        self.openWindow = openWindow
        self.openSettings = openSettings
    }

    func registerMainWindow(_ window: NSWindow) {
        window.identifier = Self.mainWindowIdentifier
        BessieWindowChromePolicy.apply(to: window)
        window.contentMinSize = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "09"
            ? NSSize(width: BessieAccessibilityContract.minimumContentWidth, height: 0)
            : BessieAccessibilityContract.minimumContentSize
        trackMainWindow(window)
    }

    func trackMainWindow(_ window: any BessieMainWindowPresenting) {
        registeredMainWindow = window
        creationPending = false
    }

    func unregisterMainWindow(_ window: NSWindow) {
        guard registeredMainWindow === window as AnyObject else { return }
        registeredMainWindow = nil
    }

    func showOrCreateMainWindow() {
        application.setActivationPolicy(.regular)
        if let window = mainWindow {
            restoreAndActivate(window)
            return
        }
        guard !creationPending, let openWindow else { return }
        creationPending = true
        openWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            creationPending = false
            if let window = mainWindow { restoreAndActivate(window) }
        }
    }

    func showSettings() {
        showOrCreateMainWindow()
        application.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            openSettings?()
            application.activate(ignoringOtherApps: true)
        }
    }

    private var mainWindow: (any BessieMainWindowPresenting)? {
        registeredMainWindow
    }

    private func restoreAndActivate(_ window: any BessieMainWindowPresenting) {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        application.unhide(nil)
        application.activate(ignoringOtherApps: true)
    }
}
