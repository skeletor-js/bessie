import AppKit
import BessieCore
import Combine
import SwiftUI

final class BessieMenuBarPopoverController: NSPopover {
    init(contentViewController: NSViewController) {
        super.init()
        self.contentViewController = contentViewController
        behavior = .transient
        animates = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

private struct BessieMenuBarThemeScope<Content: View>: View {
    @ObservedObject var settings: BessieSettingsModel
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    var body: some View {
        content.environment(
            \.bessieConcreteThemeID,
            BessieThemeRegistry.definition(
                for: settings.preferences.appearance,
                systemScheme: colorScheme
            ).id
        )
    }
}

@MainActor
final class BessieMenuBarController: NSObject {
    private let statusBar: NSStatusBar
    private let popover: BessieMenuBarPopoverController
    private let fleet: ConnectionFleetViewModel
    private let settings: BessieSettingsModel
    private weak var windowCoordinator: BessieWindowRouting?
    private let route: (RoutedPaneTarget) -> Void
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var renderedAccessibilityLabel: String?
    private var didPresentCapturePanel = false

    init(statusBar: NSStatusBar = .system, fleet: ConnectionFleetViewModel, settings: BessieSettingsModel,
         windowCoordinator: BessieWindowRouting, route: @escaping (RoutedPaneTarget) -> Void) {
        self.statusBar = statusBar
        self.fleet = fleet
        self.settings = settings
        self.windowCoordinator = windowCoordinator
        self.route = route
        let host = NSHostingController(rootView: BessieMenuBarThemeScope(
            settings: settings,
            content: BessieMenuBarPopover(
                fleet: fleet, settings: settings,
                openBessie: {}, openRow: { _ in }
            )
        ))
        popover = BessieMenuBarPopoverController(contentViewController: host)
        super.init()
        host.rootView = BessieMenuBarThemeScope(
            settings: settings,
            content: BessieMenuBarPopover(
                fleet: fleet, settings: settings,
                openBessie: { [weak self] in
                    BessieDiagnosticLog.append("Menu bar action=openBessie")
                    self?.closePopover()
                    self?.windowCoordinator?.showOrCreateMainWindow()
                },
                openRow: { [weak self] target in self?.open(target) }
            )
        )
        settings.$preferences
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        fleet.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            .store(in: &subscriptions)
        refresh()
    }

    private func refresh() {
        guard settings.preferences.menuBarVisible else {
            closePopover()
            if let statusItem { statusBar.removeStatusItem(statusItem) }
            statusItem = nil
            renderedAccessibilityLabel = nil
            return
        }
        let presentation = currentPresentation
        let badge = presentation.badgeCount(policy: settings.preferences.menuBarBadgePolicy)
        let title: String
        if let badge, badge > 0 {
            title = "\(badge)"
        } else {
            title = ""
        }
        let accessibilityLabel = presentation.badgeAccessibilityLabel(
            policy: settings.preferences.menuBarBadgePolicy
        )
        if statusItem == nil {
            let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
            item.isVisible = false
            item.button?.target = self
            item.button?.action = #selector(togglePanel(_:))
            item.button?.image = Self.statusIconImage()
            item.button?.imagePosition = .imageLeading
            item.button?.imageScaling = .scaleProportionallyDown
            item.button?.title = title
            item.button?.setAccessibilityLabel(accessibilityLabel)
            item.button?.toolTip = "Bessie"
            renderedAccessibilityLabel = accessibilityLabel
            statusItem = item
            item.isVisible = true
            BessieDiagnosticLog.append(
                "Menu bar status owner pid=\(ProcessInfo.processInfo.processIdentifier) visible=\(item.isVisible)"
            )
        }
        if statusItem?.button?.title != title {
            statusItem?.button?.title = title
        }
        if renderedAccessibilityLabel != accessibilityLabel {
            statusItem?.button?.setAccessibilityLabel(accessibilityLabel)
            renderedAccessibilityLabel = accessibilityLabel
        }
        if popover.isShown { updatePopoverSize() }
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "15", !didPresentCapturePanel {
            didPresentCapturePanel = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePanel(nil) }
        }
    }

    static func statusIconImage() -> NSImage {
        let pointSize = NSSize(width: 26, height: 18)
        guard let logoURL = BessieResources.url(forResource: "BessieMenuBarTemplate", withExtension: "png"),
              let sourceImage = NSImage(contentsOf: logoURL),
              let bitmap = sourceImage.representations.first as? NSBitmapImageRep
        else {
            preconditionFailure("Bessie could not load its menu-bar logo")
        }
        bitmap.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        image.isTemplate = true
        return image
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        BessieDiagnosticLog.append(
            "Menu bar toggle shown=\(popover.isShown) buttonWindow=\(button.window != nil)"
        )
        if popover.isShown {
            closePopover()
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func updatePopoverSize() {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        var contentSize = view.fittingSize
        contentSize.width = 312
        contentSize.height = max(contentSize.height, 183)
        popover.contentSize = contentSize
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        updatePopoverSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        BessieDiagnosticLog.append(
            "Menu bar popover shown=\(popover.isShown) width=\(Int(popover.contentSize.width)) height=\(Int(popover.contentSize.height))"
        )
        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController?.view.window?.makeKey()
        }
        captureMenuBarIfRequested(statusButton: button)
    }

    private func closePopover() {
        popover.close()
    }

    private func captureMenuBarIfRequested(statusButton: NSStatusBarButton) {
        guard let path = ProcessInfo.processInfo.environment["BESSIE_MENU_BAR_SNAPSHOT_PATH"],
              ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "15"
        else { return }
        let delay = Double(ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_DELAY"] ?? "2") ?? 2
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Capture path is verification-only. Never trap on geometry conversion.
            guard let panelView = self.popover.contentViewController?.view else { return }
            panelView.layoutSubtreeIfNeeded()
            panelView.displayIfNeeded()
            let panelBounds = panelView.bounds
            let statusBounds = statusButton.bounds
            guard panelBounds.width > 0, panelBounds.height > 0,
                  statusBounds.width > 0, statusBounds.height > 0,
                  let panelImage = panelView.bitmapImageRepForCachingDisplay(in: panelBounds),
                  let statusImage = statusButton.bitmapImageRepForCachingDisplay(in: statusBounds)
            else { return }
            panelView.cacheDisplay(in: panelBounds, to: panelImage)
            statusButton.layoutSubtreeIfNeeded()
            statusButton.cacheDisplay(in: statusBounds, to: statusImage)
            guard let panelCGImage = panelImage.cgImage,
                  let statusCGImage = statusImage.cgImage
            else { return }
            let canvasW = 900
            let canvasH = 470
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: canvasW,
                pixelsHigh: canvasH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
            let destination = context.cgContext
            destination.clear(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
            let panelW = min(max(self.popover.contentSize.width, 1), CGFloat(canvasW))
            let panelH = min(max(self.popover.contentSize.height, 1), CGFloat(canvasH))
            let statusW = min(max(statusBounds.width, 1), CGFloat(canvasW))
            let statusH = min(max(statusBounds.height, 1), CGFloat(canvasH))
            destination.draw(panelCGImage, in: CGRect(
                x: CGFloat(canvasW) - panelW - 14,
                y: CGFloat(canvasH) - statusH - 4 - panelH,
                width: panelW,
                height: panelH
            ))
            destination.draw(statusCGImage, in: CGRect(
                x: 795,
                y: CGFloat(canvasH) - statusH,
                width: statusW,
                height: statusH
            ))
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            let url = URL(fileURLWithPath: path)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: url, options: .atomic)
            BessieDiagnosticLog.append("Menu-bar snapshot path=\(path) width=\(canvasW) height=\(canvasH)")
        }
    }

    private func open(_ target: RoutedPaneTarget) {
        closePopover()
        windowCoordinator?.showOrCreateMainWindow()
        guard settings.preferences.menuBarRowClickBehavior == .focusPane else { return }
        guard !Self.isCurrent(target, among: fleet.agents, freshConnectionIDs: fleet.connectedConnectionIDs) else {
            route(target)
            return
        }
        Task { @MainActor in
            await fleet.scheduleRefresh().value
            if Self.isCurrent(target, among: fleet.agents, freshConnectionIDs: fleet.connectedConnectionIDs) {
                route(target)
            } else {
                fleet.reportRouteFailure(
                    "That menu-bar target is no longer available. Bessie refreshed The herd; choose its current pane there."
                )
            }
        }
    }

    private var currentPresentation: BessieMenuBarPresentation {
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "15" {
            return .captureFixture
        }
        return BessieMenuBarPresentation(
            agents: fleet.agents,
            freshConnectionIDs: fleet.connectedConnectionIDs,
            snoozedIncarnations: settings.snoozedPaneIncarnations()
        )
    }

    static func isCurrent(
        _ target: RoutedPaneTarget,
        among agents: [ConnectedAgentProjection],
        freshConnectionIDs: Set<String>
    ) -> Bool {
        freshConnectionIDs.contains(target.connectionID) && agents.contains {
            $0.connectionID == target.connectionID
                && $0.workspaceID == target.workspaceID
                && $0.tabID == target.tabID
                && $0.paneID == target.paneID
        }
    }
}
