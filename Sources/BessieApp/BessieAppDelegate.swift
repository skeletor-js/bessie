import AppKit

@MainActor
final class BessieAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var doubleClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bessie_windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSApp.windows.forEach(configureWindow(_:))
        installTitlebarDoubleClickMonitor()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    @objc private func bessie_windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        // Keep a real titlebar so traffic lights + the strip ABOVE content work natively.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.title = "Bessie"
        if window.delegate !== self {
            window.delegate = self
        }
    }

    /// Double-click the native titlebar strip (above content, beside traffic lights) → full screen.
    private func installTitlebarDoubleClickMonitor() {
        guard doubleClickMonitor == nil else { return }
        doubleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard event.clickCount == 2,
                  let window = event.window,
                  self?.isBessieMainWindow(window) == true
            else { return event }

            // Titlebar is the band above contentLayoutRect (AppKit coords: origin bottom-left).
            let layout = window.contentLayoutRect
            let point = event.locationInWindow
            let inTitlebarBand = point.y >= layout.maxY - 1
            // Ignore clicks on traffic-light buttons (far left).
            let pastTrafficLights = point.x > 78
            if inTitlebarBand, pastTrafficLights {
                window.toggleFullScreen(nil)
                return nil
            }
            return event
        }
    }

    private func isBessieMainWindow(_ window: NSWindow) -> Bool {
        // Settings / sheets excluded roughly by style + title.
        window.styleMask.contains(.titled) && window.contentView != nil
    }

    func window(
        _ window: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        proposedOptions.union([.autoHideToolbar, .fullScreen, .autoHideDock])
    }
}
