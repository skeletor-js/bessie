import AppKit
import XCTest
@testable import BessieApp
@testable import BessieCore

private final class MenuBarWindowSpy: BessieMainWindowPresenting {
    var reportsMiniaturized = true
    private(set) var didDeminiaturize = false
    private(set) var didMakeKeyAndOrderFront = false

    var isMiniaturized: Bool { reportsMiniaturized }

    func deminiaturize(_ sender: Any?) {
        didDeminiaturize = true
        reportsMiniaturized = false
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        didMakeKeyAndOrderFront = true
    }
}

@MainActor
final class MenuBarPresentationTests: XCTestCase {
    func testMenuBarPopoverUsesNativeTransientLifecycle() {
        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 312, height: 183))
        let popover = BessieMenuBarPopoverController(contentViewController: content)
        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let button = NSButton(frame: NSRect(x: 40, y: 40, width: 24, height: 24))
        window.contentView?.addSubview(button)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.orderFront(nil)

        XCTAssertEqual(popover.behavior, .transient)
        XCTAssertFalse(popover.animates)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        XCTAssertTrue(popover.isShown)

        let didClose = expectation(forNotification: NSPopover.didCloseNotification, object: popover)
        popover.close()

        wait(for: [didClose], timeout: 0.5)
        XCTAssertFalse(popover.isShown)
        button.removeFromSuperview()
        window.orderOut(nil)
        window.close()
    }

    func testStatusIconIsATransparentMonochromeTemplateAtFullScale() throws {
        let image = BessieMenuBarController.statusIconImage()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.height, 18)
        XCTAssertEqual(image.size.width / image.size.height, 952.0 / 657.0, accuracy: 0.05)
        XCTAssertEqual(image.representations.count, 1)
        let sourceBitmap = try XCTUnwrap(image.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(sourceBitmap.size, image.size)
        XCTAssertEqual(sourceBitmap.pixelsWide, 52)
        XCTAssertEqual(sourceBitmap.pixelsHigh, 36)

        let pixelsWide = 52
        let pixelsHigh = 36
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.cgContext.fill(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let corners = [
            (0, 0),
            (0, pixelsHigh - 1),
            (pixelsWide - 1, 0),
            (pixelsWide - 1, pixelsHigh - 1),
        ]
        for (x, y) in corners {
            XCTAssertEqual(bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1, 0, accuracy: 0.01)
        }

        var visiblePixelCount = 0
        var minX = pixelsWide
        var maxX = -1
        var minY = pixelsHigh
        var maxY = -1
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 else { continue }
                visiblePixelCount += 1
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.05)
                XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.05)
            }
        }

        let totalPixelCount = pixelsWide * pixelsHigh
        XCTAssertGreaterThan(visiblePixelCount, totalPixelCount / 5)
        XCTAssertLessThan(Double(visiblePixelCount) / Double(totalPixelCount), 0.85)
        XCTAssertGreaterThanOrEqual(Double(maxX - minX + 1) / Double(pixelsWide), 0.9)
        XCTAssertGreaterThanOrEqual(Double(maxY - minY + 1) / Double(pixelsHigh), 0.9)
    }

    func testStatusIconTemplateRendersBlackInLightAppearanceAndWhiteInDarkAppearance() throws {
        let light = try renderedStatusIcon(appearance: .aqua)
        let dark = try renderedStatusIcon(appearance: .darkAqua)

        XCTAssertLessThan(try averageVisibleLuminance(light), 0.05)
        XCTAssertGreaterThan(try averageVisibleLuminance(dark), 0.95)
    }

    func testPresentationCountsOnlyFreshStatesAndKeepsDisconnectedHealth() {
        let local = BessieConnectionDefinition.localBessie
        let stale = BessieConnectionDefinition(name: "Remote", kind: .ssh, sshHost: "remote", session: nil)
        let agents = [
            agent("blocked", pane: "p1", connection: local),
            agent("working", pane: "p2", connection: local),
            agent("done", pane: "p3", connection: local),
            agent("idle", pane: "p4", connection: local),
            agent("unknown", pane: "p5", connection: local),
            agent("blocked", pane: "stale", connection: stale),
        ]
        let health = [
            ConnectionHealth(connection: local, presentation: .connectedFixture),
            ConnectionHealth(connection: stale, presentation: ConnectPresentation(
                title: "Disconnected", detail: "Unavailable", status: .lost
            )),
        ]

        let presentation = BessieMenuBarPresentation(
            agents: agents,
            freshConnectionIDs: [local.id],
            connections: [local, stale],
            health: health
        )

        XCTAssertEqual(presentation.needsYou.map(\.target.paneID), ["p1"])
        XCTAssertEqual(presentation.needsYou.first?.title, "p1")
        XCTAssertEqual(presentation.needsYou.first?.location, "This Mac · Workspace · Tab")
        XCTAssertEqual(presentation.needsYou.first?.provider, "codex")
        XCTAssertEqual(presentation.workingRows.map(\.target.paneID), ["p2"])
        XCTAssertEqual(presentation.working, 1)
        XCTAssertEqual(presentation.settled, 2)
        XCTAssertEqual(presentation.unknown, 1)
        XCTAssertEqual(presentation.health.count, 2)
        XCTAssertFalse(presentation.health.first { $0.id == stale.id }!.connected)
        XCTAssertEqual(presentation.badgeCount(policy: .needsYou), 1)
        XCTAssertEqual(presentation.badgeCount(policy: .needsYouAndUnknown), 2)
        XCTAssertNil(presentation.badgeCount(policy: .nothing))
    }

    func testFreshAllZeroPresentationIsCompleteAndBadgeIsZero() {
        let presentation = BessieMenuBarPresentation(
            agents: [],
            freshConnectionIDs: [BessieConnectionDefinition.localBessie.id],
            connections: [.localBessie],
            health: [ConnectionHealth(connection: .localBessie, presentation: .connectedFixture)]
        )

        XCTAssertTrue(presentation.needsYou.isEmpty)
        XCTAssertTrue(presentation.workingRows.isEmpty)
        XCTAssertEqual(presentation.working, 0)
        XCTAssertEqual(presentation.settled, 0)
        XCTAssertEqual(presentation.unknown, 0)
        XCTAssertEqual(presentation.health.count, 1)
        XCTAssertEqual(presentation.badgeCount(policy: .needsYou), 0)
    }

    func testBadgeAccessibilityNamesTheHonestPolicyState() {
        let presentation = BessieMenuBarPresentation.captureFixture

        XCTAssertEqual(
            presentation.badgeAccessibilityLabel(policy: .needsYou),
            "Bessie, 2 agents need you"
        )
        XCTAssertEqual(
            presentation.badgeAccessibilityLabel(policy: .needsYouAndUnknown),
            "Bessie, 2 agents need you, 1 unknown"
        )
        XCTAssertEqual(presentation.badgeAccessibilityLabel(policy: .nothing), "Bessie")
    }

    func testAppAlwaysSurvivesLastWindowWithCompanionPreferenceEitherWay() {
        let delegate = BessieAppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
    }

    func testOnlyTheMainWindowReceivesBessieChrome() {
        XCTAssertTrue(BessieWindowChromePolicy.applies(
            isPanel: false,
            identifier: nil,
            title: "Bessie"
        ))
        XCTAssertFalse(BessieWindowChromePolicy.applies(
            isPanel: true,
            identifier: nil,
            title: "Bessie"
        ))
        XCTAssertFalse(BessieWindowChromePolicy.applies(
            isPanel: false,
            identifier: nil,
            title: "Settings"
        ))
        XCTAssertTrue(BessieWindowChromePolicy.applies(
            isPanel: false,
            identifier: BessieWindowChromePolicy.mainWindowIdentifier,
            title: "Settings"
        ))
    }

    func testWindowCoordinatorCoalescesConcurrentWindowCreationRequests() {
        let coordinator = BessieWindowCoordinator()
        var creationCount = 0
        coordinator.install { creationCount += 1 }

        coordinator.showOrCreateMainWindow()
        coordinator.showOrCreateMainWindow()
        coordinator.showOrCreateMainWindow()

        XCTAssertEqual(creationCount, 1)
    }

    func testWindowCoordinatorUsesInstalledSwiftUISettingsAction() async {
        let coordinator = BessieWindowCoordinator()
        let opened = expectation(description: "Settings opened")
        coordinator.install(openWindow: {}, openSettings: { opened.fulfill() })

        coordinator.showSettings()

        await fulfillment(of: [opened], timeout: 0.5)
    }

    func testWindowCoordinatorRestoresRegisteredWindowWithoutCreatingAnother() {
        let coordinator = BessieWindowCoordinator()
        let window = MenuBarWindowSpy()
        var creationCount = 0
        coordinator.install { creationCount += 1 }
        coordinator.trackMainWindow(window)

        coordinator.showOrCreateMainWindow()

        XCTAssertEqual(creationCount, 0)
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertTrue(window.didDeminiaturize)
        XCTAssertTrue(window.didMakeKeyAndOrderFront)
    }

    func testClosedMainWindowIsUnregisteredAndRecreatedOnce() {
        let delegate = BessieAppDelegate()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        var creationCount = 0
        let releaseNotification = expectation(description: "main-window terminal release")
        delegate.windowCoordinator.install { creationCount += 1 }
        delegate.windowCoordinator.registerMainWindow(window)
        let observer = NotificationCenter.default.addObserver(
            forName: .bessieMainWindowWillClose,
            object: window,
            queue: nil
        ) { _ in releaseNotification.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        delegate.windowCoordinator.showOrCreateMainWindow()
        delegate.windowCoordinator.showOrCreateMainWindow()

        wait(for: [releaseNotification], timeout: 0.1)
        XCTAssertEqual(creationCount, 1)
        window.close()
    }

    func testMenuBarRouteRequiresTheExactFreshPaneTarget() {
        let local = BessieConnectionDefinition.localBessie
        let current = agent("blocked", pane: "current", connection: local)
        let currentTarget = RoutedPaneTarget(
            connectionID: local.id,
            workspaceID: current.workspaceID,
            tabID: current.tabID,
            paneID: current.paneID
        )
        let staleTarget = RoutedPaneTarget(
            connectionID: local.id,
            workspaceID: "old-workspace",
            tabID: current.tabID,
            paneID: current.paneID
        )

        XCTAssertTrue(BessieMenuBarController.isCurrent(currentTarget, among: [current], freshConnectionIDs: [local.id]))
        XCTAssertFalse(BessieMenuBarController.isCurrent(staleTarget, among: [current], freshConnectionIDs: [local.id]))
        XCTAssertFalse(BessieMenuBarController.isCurrent(currentTarget, among: [current], freshConnectionIDs: []))
    }

    private func renderedStatusIcon(appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let statusItem = NSStatusBar.system.statusItem(withLength: 30)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let button = try XCTUnwrap(statusItem.button)
        button.image = BessieMenuBarController.statusIconImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.appearance = NSAppearance(named: appearance)
        button.layoutSubtreeIfNeeded()
        button.displayIfNeeded()
        XCTAssertEqual(button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), appearance)

        let scale = 2
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(button.bounds.width) * scale,
            pixelsHigh: Int(button.bounds.height) * scale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = button.bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(button.bounds)
        button.cacheDisplay(in: button.bounds, to: bitmap)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private func averageVisibleLuminance(_ bitmap: NSBitmapImageRep) throws -> CGFloat {
        var luminance: CGFloat = 0
        var visiblePixelCount = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
                guard color.alphaComponent > 0.01 else { continue }
                luminance += 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                visiblePixelCount += 1
            }
        }
        XCTAssertGreaterThan(visiblePixelCount, 100)
        return luminance / CGFloat(visiblePixelCount)
    }

    private func agent(
        _ state: String,
        pane: String,
        connection: BessieConnectionDefinition
    ) -> ConnectedAgentProjection {
        ConnectedAgentProjection(
            connection: connection,
            agent: AgentProjection(
                id: pane, terminalID: "t-\(pane)", workspaceID: "w", tabID: "t", focused: false,
                label: nil, agent: "codex", displayAgent: nil, name: pane, title: nil,
                agentStatus: state, revision: 1, launchPending: false
            ),
            workspaceLabel: "Workspace",
            tabLabel: "Tab"
        )
    }
}

private extension ConnectPresentation {
    static let connectedFixture = ConnectPresentation(title: "Connected", detail: "Ready", status: .connected)
}
