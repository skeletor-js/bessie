import AppKit
import BessieCore
import Combine

enum BessieWindowChromePolicy {
    static let mainWindowIdentifier = "Bessie.mainWindow"

    static func applies(isPanel: Bool, identifier: String?, title: String) -> Bool {
        guard !isPanel else { return false }
        return identifier == mainWindowIdentifier || title == "Bessie"
    }

    static func isFullScreen(
        isPanel: Bool,
        identifier: String?,
        title: String,
        styleMask: NSWindow.StyleMask
    ) -> Bool {
        applies(isPanel: isPanel, identifier: identifier, title: title)
            && styleMask.contains(.fullScreen)
    }

    @MainActor
    static func isFullScreen(_ window: NSWindow) -> Bool {
        isFullScreen(
            isPanel: window is NSPanel,
            identifier: window.identifier?.rawValue,
            title: window.title,
            styleMask: window.styleMask
        )
    }

    @MainActor
    static func apply(to window: NSWindow) {
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.toolbar = nil
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor(BessieDesign.window.currentColor)
    }
}

@MainActor
final class BessieAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let windowCoordinator = BessieWindowCoordinator()
    private var menuBarController: BessieMenuBarController?
    private weak var fleet: ConnectionFleetViewModel?
    private weak var settings: BessieSettingsModel?
    private weak var notifications: BessieNotificationCoordinator?
    private var fleetCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var configured = false
    private weak var fullscreenAutomationWindow: NSWindow?

    func configure(
        fleet: ConnectionFleetViewModel,
        settings: BessieSettingsModel,
        notifications: BessieNotificationCoordinator,
        openWindow: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        windowCoordinator.install(openWindow: openWindow, openSettings: openSettings)
        guard !configured else { return }
        configured = true
        self.fleet = fleet
        self.settings = settings
        self.notifications = notifications
        notifications.activationHandler = { [weak windowCoordinator] in
            windowCoordinator?.showOrCreateMainWindow()
        }
        menuBarController = BessieMenuBarController(
            fleet: fleet,
            settings: settings,
            windowCoordinator: windowCoordinator
        ) { target in
            notifications.enqueueRoute(target)
        }
        // Fleet-lifetime notification reconcile. Survives main-window close so the
        // menu-bar companion still emits. When the main window is open, the product
        // shell still owns the *active* connection (better activePaneID suppression).
        fleetCancellable = fleet.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.reconcileFleetNotifications() }
        }
        settingsCancellable = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.reconcileFleetNotifications() }
        }
        reconcileFleetNotifications()
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "15" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.windows.forEach { $0.orderOut(nil) }
            }
        }
    }

    /// Reconcile notification transitions for connections the window shell may not own.
    func reconcileFleetNotifications() {
        guard let fleet, let settings, let notifications else { return }
        // Snapshot availability is transient. Retain notification history for every
        // configured connection so reconnects do not reseed or erase valid delivery.
        notifications.retainConnections(Set(fleet.connectionDefinitions.map(\.id)))
        let mainWindowOpen = NSApp.windows.contains {
            $0.identifier?.rawValue == BessieWindowChromePolicy.mainWindowIdentifier && $0.isVisible
        }
        reconcileFleetNotificationSources(
            fleet.notificationSources,
            activeConnectionID: fleet.activeConnectionID,
            mainWindowOpen: mainWindowOpen,
            policy: settings.preferences.notifications,
            snoozedIncarnations: settings.snoozedPaneIncarnations(),
            notifications: notifications
        )
    }

    func reconcileFleetNotificationSources(
        _ sources: [FleetNotificationSource],
        activeConnectionID: String?,
        mainWindowOpen: Bool,
        policy: BessieNotifications,
        snoozedIncarnations: Set<BessiePaneIncarnation>,
        notifications: BessieNotificationCoordinator
    ) {
        // Policy applies to all tracked requests, including configured connections
        // that are temporarily absent from the current fleet projection.
        notifications.reconcilePolicy(policy)
        for source in sources {
            let isActive = source.connection.id == activeConnectionID
            if mainWindowOpen && isActive {
                // Product shell owns active-connection reconcile while the window lives.
                continue
            }
            notifications.reconcile(
                connection: source.connection,
                panes: source.panes,
                policy: policy,
                activePaneID: nil,
                snoozedIncarnations: snoozedIncarnations
            )
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(bessie_windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSApp.windows.forEach(configureWindow(_:))
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        fleet?.stopIntentServer()
        fleet?.stop()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool { false }

    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowCoordinator.showOrCreateMainWindow()
        return true
    }

    func quitBessie() {
        NSApplication.shared.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == BessieWindowCoordinator.mainWindowIdentifier
        else { return }
        NotificationCenter.default.post(name: .bessieMainWindowWillClose, object: window)
        windowCoordinator.unregisterMainWindow(window)
        // Window shell is going away — take over active-connection notify watching.
        DispatchQueue.main.async { [weak self] in
            self?.reconcileFleetNotifications()
        }
    }

    @objc private func bessie_windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        configureWindow(window)
    }

    private func configureWindow(_ window: NSWindow) {
        guard Self.shouldApplyMainWindowChrome(to: window) else { return }
        BessieWindowChromePolicy.apply(to: window)
        window.collectionBehavior.insert(.fullScreenPrimary)
        if let frame = ProcessInfo.processInfo.environment["BESSIE_CAPTURE_FRAME"]?.split(separator: "x"),
           frame.count == 2, let width = Double(frame[0]), let height = Double(frame[1]) {
            let chromeHeight = max(0, window.frame.height - window.contentLayoutRect.height)
            window.setContentSize(NSSize(width: width, height: height))
            if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "08",
               window.contentLayoutRect.height < height {
                window.setFrame(NSRect(x: window.frame.minX, y: 0, width: width, height: height + chromeHeight), display: true)
            }
        }
        if window.delegate !== self {
            window.delegate = self
        }
        if ProcessInfo.processInfo.environment["BESSIE_FULLSCREEN_SNAPSHOT"] == "1",
           fullscreenAutomationWindow !== window {
            fullscreenAutomationWindow = window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
                guard let window, !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }
    }

    static func shouldApplyMainWindowChrome(to window: NSWindow) -> Bool {
        BessieWindowChromePolicy.applies(
            isPanel: window is NSPanel,
            identifier: window.identifier?.rawValue,
            title: window.title
        )
    }

}
