import AppKit
import BessieCore
import Combine
import Foundation
import GhosttyTerminal
import SwiftUI

enum TerminalSurfaceStreamAction: Equatable {
    case startStream
    case keepStream
}

@MainActor
enum TerminalThemeTransaction {
    struct Target {
        let apply: (BessieResolvedTerminalTheme) -> Bool
    }

    static func apply(
        candidate: BessieResolvedTerminalTheme,
        previous: BessieResolvedTerminalTheme,
        targets: [Target]
    ) -> Bool {
        var updated: [Target] = []
        for target in targets {
            guard target.apply(candidate) else {
                for applied in updated.reversed() {
                    _ = applied.apply(previous)
                }
                return false
            }
            updated.append(target)
        }
        return true
    }
}

struct TerminalSurfaceStreamLifecycle {
    private(set) var streamStarted = false

    mutating func attach() -> TerminalSurfaceStreamAction {
        guard !streamStarted else { return .keepStream }
        streamStarted = true
        return .startStream
    }

    mutating func detach() {
        // The same libghostty view and in-memory session remain alive while parked.
    }
}

struct TerminalSurfacePresentationTracker {
    private(set) var attachmentToken: UUID?
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0

    mutating func requiresFullPresentation(
        attachmentToken: UUID,
        width: CGFloat,
        height: CGFloat
    ) -> Bool {
        guard width > 0, height > 0 else { return false }
        let changed = self.attachmentToken != attachmentToken
            || self.width != width
            || self.height != height
        guard changed else { return false }
        self.attachmentToken = attachmentToken
        self.width = width
        self.height = height
        return true
    }

    mutating func reset() {
        attachmentToken = nil
        width = 0
        height = 0
    }
}

@MainActor
final class WarmTerminalControllerStore<Controller: AnyObject> {
    private(set) var controllers: [String: Controller] = [:]
    private(set) var presentedPaneIDs: [String] = []
    private(set) var warmPaneIDs: [String] = []
    private let warmCapacity: Int
    private let create: (String) -> Controller
    private let release: (Controller) -> Void

    init(
        warmCapacity: Int,
        create: @escaping (String) -> Controller,
        release: @escaping (Controller) -> Void
    ) {
        self.warmCapacity = max(0, warmCapacity)
        self.create = create
        self.release = release
    }

    func reconcile(
        presentedPaneIDs: [String],
        availablePaneIDs: Set<String>,
        prewarmPaneIDs: [String] = []
    ) {
        let presented = presentedPaneIDs.reduce(into: [String]()) { result, paneID in
            if availablePaneIDs.contains(paneID), !result.contains(paneID) { result.append(paneID) }
        }
        let prewarm = prewarmPaneIDs.reduce(into: [String]()) { result, paneID in
            if availablePaneIDs.contains(paneID),
               !presented.contains(paneID),
               !result.contains(paneID),
               result.count < warmCapacity {
                result.append(paneID)
            }
        }

        for paneID in controllers.keys.filter({ !availablePaneIDs.contains($0) }).sorted() {
            remove(paneID)
        }
        warmPaneIDs.removeAll { !availablePaneIDs.contains($0) }

        for paneID in presented + prewarm where controllers[paneID] == nil {
            controllers[paneID] = create(paneID)
        }

        let nextPresented = Set(presented)
        let leaving = self.presentedPaneIDs.filter { !nextPresented.contains($0) && controllers[$0] != nil }
        warmPaneIDs.removeAll {
            nextPresented.contains($0) || leaving.contains($0) || prewarm.contains($0)
        }
        for paneID in leaving + prewarm where !warmPaneIDs.contains(paneID) {
            warmPaneIDs.append(paneID)
        }
        self.presentedPaneIDs = presented

        while warmPaneIDs.count > warmCapacity {
            remove(warmPaneIDs.removeFirst())
        }
    }

    func removeAll() {
        for paneID in controllers.keys.sorted() { remove(paneID) }
        presentedPaneIDs.removeAll()
        warmPaneIDs.removeAll()
    }

    private func remove(_ paneID: String) {
        warmPaneIDs.removeAll { $0 == paneID }
        presentedPaneIDs.removeAll { $0 == paneID }
        if let controller = controllers.removeValue(forKey: paneID) { release(controller) }
    }
}

@MainActor
final class TerminalControllerPrewarmer {
    private let window: NSWindow
    private let container: NSView

    init(size: NSSize = NSSize(width: 1280, height: 720)) {
        container = NSView(frame: NSRect(origin: .zero, size: size))
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.orderOut(nil)
    }

    func reconcile(
        controllers: [String: PaneTerminalController],
        warmPaneIDs: [String]
    ) {
        let warm = Set(warmPaneIDs)
        for (paneID, controller) in controllers {
            controller.setPrewarming(warm.contains(paneID))
        }

        for paneID in warmPaneIDs {
            guard let controller = controllers[paneID], !controller.hasStartedStream else { continue }
            let host = TerminalSurfaceHostView(frame: container.bounds)
            host.autoresizingMask = [.width, .height]
            container.addSubview(host)
            host.attach(
                controller: controller,
                fontSize: 13,
                requestFocus: {},
                responderChanged: { _ in }
            )
            host.layoutSubtreeIfNeeded()
            host.detach()
            host.removeFromSuperview()
            if !controller.hasStartedStream {
                BessieDiagnosticLog.append("Terminal prewarm pane=\(paneID) did not attach a native surface")
            }
        }
    }
}

@MainActor
final class TerminalControllerRegistry: ObservableObject {
    static let defaultWarmCapacity = 12
    @Published private(set) var controllers: [String: PaneTerminalController] = [:]
    @Published private(set) var diagnosticRevision = 0
    private var endpoint: HerdrTerminalEndpoint?
    private var diagnosticSubscriptions: [String: AnyCancellable] = [:]
    private let performanceRecorder: BessiePerformanceRecorder
    private let prewarmer = TerminalControllerPrewarmer()
    private var store: WarmTerminalControllerStore<PaneTerminalController>!
    private var pendingSwitches: [String: UInt64] = [:]
    private var pendingSwitchStartedAt: [String: TimeInterval] = [:]
    private var pendingFocusPaneID: String?
    private var pendingFocusRefresh: PaneTerminalController.SurfaceRefresh = .full
    private var paneIncarnations: [String: BessiePaneIncarnation] = [:]
    private var recordLocalPaneUse: (BessiePaneIncarnation) -> Void = { _ in }
    private(set) var effectiveTheme = BessieThemeRegistry.definitions[.dark]!.resolvedTerminalTheme

    init(
        warmCapacity: Int = defaultWarmCapacity,
        performanceRecorder: BessiePerformanceRecorder = BessiePerformance.recorder
    ) {
        self.performanceRecorder = performanceRecorder
        store = WarmTerminalControllerStore(
            warmCapacity: warmCapacity,
            create: { [weak self] paneID in
                guard let self, let endpoint = self.endpoint else {
                    preconditionFailure("Terminal controller creation requires an endpoint")
                }
                return PaneTerminalController(
                    paneID: paneID,
                    endpoint: endpoint,
                    theme: self.effectiveTheme,
                    performanceRecorder: performanceRecorder,
                    recordLocalUse: { [weak self, incarnation = self.paneIncarnations[paneID]] in
                        guard let self, let incarnation else { return }
                        self.recordLocalPaneUse(incarnation)
                    },
                    surfacePresented: { [weak self] in self?.recordSwitchSurfaceAttached(paneID: paneID) }
                )
            },
            release: { $0.release() }
        )
    }

    func configureLocalPaneUse(
        incarnations: [String: BessiePaneIncarnation],
        record: @escaping (BessiePaneIncarnation) -> Void
    ) {
        paneIncarnations = incarnations
        recordLocalPaneUse = record
        for (paneID, controller) in controllers {
            controller.recordLocalUse = { [weak self, incarnation = incarnations[paneID]] in
                guard let self, let incarnation else { return }
                self.recordLocalPaneUse(incarnation)
            }
        }
    }

    func setInitialTheme(_ theme: BessieResolvedTerminalTheme) {
        precondition(controllers.isEmpty)
        effectiveTheme = theme
    }

    @discardableResult
    func applyTheme(_ candidate: BessieResolvedTerminalTheme) -> Bool {
        guard candidate != effectiveTheme else { return true }
        let previous = effectiveTheme
        let targets = controllers.keys.sorted().compactMap { paneID -> TerminalThemeTransaction.Target? in
            guard let controller = controllers[paneID] else { return nil }
            return TerminalThemeTransaction.Target { [weak controller] theme in
                controller?.updateTheme(theme) == true
            }
        }
        guard TerminalThemeTransaction.apply(candidate: candidate, previous: previous, targets: targets) else {
            BessieDiagnosticLog.append("Terminal theme transaction rejected; prior theme retained")
            return false
        }
        effectiveTheme = candidate
        return true
    }

    func reconcile(
        presentedPaneIDs: [String],
        availablePaneIDs: Set<String>,
        prewarmPaneIDs: [String] = [],
        endpoint: HerdrTerminalEndpoint
    ) {
        if self.endpoint != endpoint {
            releaseAll()
            self.endpoint = endpoint
        }
        let previousIDs = Set(store.controllers.keys)
        store.reconcile(
            presentedPaneIDs: presentedPaneIDs,
            availablePaneIDs: availablePaneIDs,
            prewarmPaneIDs: prewarmPaneIDs
        )
        if !Self.sameControllers(controllers, store.controllers) {
            controllers = store.controllers
        }
        prewarmer.reconcile(controllers: controllers, warmPaneIDs: store.warmPaneIDs)
        let nextIDs = Set(controllers.keys)
        for paneID in nextIDs.subtracting(previousIDs) {
            guard let controller = controllers[paneID] else { continue }
            diagnosticSubscriptions[paneID] = controller.$status.sink { [weak self] _ in
                self?.diagnosticRevision += 1
            }
        }
        for paneID in previousIDs.subtracting(nextIDs) {
            diagnosticSubscriptions[paneID] = nil
            pendingSwitches[paneID] = nil
            pendingSwitchStartedAt[paneID] = nil
            if pendingFocusPaneID == paneID {
                pendingFocusPaneID = nil
                pendingFocusRefresh = .full
            }
        }
    }

    func recordSwitchRequested(paneID: String) {
        let sequence = performanceRecorder.nextSequence()
        pendingSwitches[paneID] = sequence
        pendingSwitchStartedAt[paneID] = ProcessInfo.processInfo.systemUptime
        performanceRecorder.mark(.terminalSwitchRequested, sequence: sequence)
        let interactivelyPresented = isInteractivelyPresented(paneID)
        BessieDiagnosticLog.append("Terminal switch pane=\(paneID) stage=requested surface_presented=\(interactivelyPresented)")
        if interactivelyPresented {
            recordSwitchSurfaceAttached(paneID: paneID)
        }
    }

    func focusWhenPresented(paneID: String, refresh: PaneTerminalController.SurfaceRefresh = .display) {
        pendingFocusPaneID = paneID
        pendingFocusRefresh = refresh
        guard isInteractivelyPresented(paneID) else { return }
        activatePresentedSurface(paneID: paneID, refresh: refresh)
    }

    func releaseAll() {
        guard endpoint != nil || !controllers.isEmpty || !diagnosticSubscriptions.isEmpty || !pendingSwitches.isEmpty else {
            return
        }
        store.removeAll()
        controllers = [:]
        diagnosticSubscriptions.removeAll()
        pendingSwitches.removeAll()
        pendingSwitchStartedAt.removeAll()
        pendingFocusPaneID = nil
        pendingFocusRefresh = .full
        endpoint = nil
        diagnosticRevision += 1
    }

    func releaseAll(unlessConnectedTo connectionID: String?) {
        guard endpoint?.connectionID != connectionID else { return }
        releaseAll()
    }

    private static func sameControllers(
        _ lhs: [String: PaneTerminalController],
        _ rhs: [String: PaneTerminalController]
    ) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy { key, controller in rhs[key] === controller }
    }

    private func isInteractivelyPresented(_ paneID: String) -> Bool {
        store.presentedPaneIDs.contains(paneID)
            && controllers[paneID]?.isSurfacePresented == true
    }

    private func recordSwitchSurfaceAttached(paneID: String) {
        if let sequence = pendingSwitches.removeValue(forKey: paneID) {
            performanceRecorder.mark(.terminalSwitchSurfaceAttached, sequence: sequence)
        }
        if let startedAt = pendingSwitchStartedAt[paneID] {
            let elapsed = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            BessieDiagnosticLog.append(String(
                format: "Terminal switch pane=%@ stage=host_attached elapsed_ms=%.1f",
                paneID,
                elapsed
            ))
        }
        if pendingFocusPaneID == paneID {
            let refresh = pendingFocusRefresh
            activatePresentedSurface(paneID: paneID, refresh: refresh)
        }
    }

    private func activatePresentedSurface(
        paneID: String,
        refresh: PaneTerminalController.SurfaceRefresh
    ) {
        guard let controller = controllers[paneID], isInteractivelyPresented(paneID) else { return }
        if pendingFocusPaneID == paneID {
            pendingFocusPaneID = nil
            pendingFocusRefresh = .full
        }
        // One activation path: focus + a single refresh mode. Full is for park/reattach;
        // display-only is for already-mounted same-tab hops (avoids Herdr resize storms).
        controller.makeTerminalFirstResponder(refresh: refresh)

        guard BessieDiagnosticLog.isEnabled else {
            pendingSwitchStartedAt[paneID] = nil
            return
        }
        guard let startedAt = pendingSwitchStartedAt[paneID] else { return }
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, let controller,
                  self.pendingSwitchStartedAt[paneID] == startedAt
            else { return }
            // Flush pending AppKit display work after selection/host attachment. This is
            // diagnostic only and lets us distinguish main-thread/display stalls from RPC.
            controller.terminalView.displayIfNeeded()
            let elapsed = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            BessieDiagnosticLog.append(String(
                format: "Terminal switch pane=%@ stage=display_flushed elapsed_ms=%.1f status=%@",
                paneID,
                elapsed,
                controller.status.diagnosticLabel
            ))
            self.pendingSwitchStartedAt[paneID] = nil
        }
    }

    var diagnosticFacts: TerminalControllerFacts {
        controllers.values.reduce(into: TerminalControllerFacts()) { facts, controller in
            if controller.themeConfigurationError != nil {
                facts.failed += 1
                return
            }
            switch controller.status {
            case .ready: facts.ready += 1
            case .reconnecting: facts.reconnecting += 1
            case .ownershipConflict: facts.ownershipConflicts += 1
            case .failed: facts.failed += 1
            case .starting, .waitingForFull, .stopped: break
            }
        }
    }
}

@MainActor
final class PaneTerminalController: ObservableObject, Identifiable {
    let id: String
    let ghosttyController: TerminalController
    let session: InMemoryTerminalSession
    let herdrController: HerdrTerminalController
    let inputRouter: TerminalInputRouter
    let terminalView: BessieTerminalView
    @Published private(set) var status: TerminalControllerStatus = .starting
    @Published private(set) var sessionMode: TerminalSessionMode = .control
    @Published private(set) var themeConfigurationError: String?
    private let bridge: PaneTerminalBridge
    private let surfacePresented: () -> Void
    private let performanceRecorder: BessiePerformanceRecorder
    private var automationStarted = false
    private var performanceProbeStarted = false
    private var resizePerformanceSequence: UInt64?
    private var resizePerformanceTarget: TerminalGrid?
    private var surfaceLifecycle = TerminalSurfaceStreamLifecycle()
    private var released = false
    private var isPrewarming = false
    private var lastAutoTakeoverAt: TimeInterval = 0
    private var configuredFontSize = 13.0
    private var configuredTheme: BessieResolvedTerminalTheme?
    private let localUseCallback: PaneLocalUseCallback
    var recordLocalUse: () -> Void {
        didSet { localUseCallback.update(recordLocalUse) }
    }

    init(
        paneID: String,
        endpoint: HerdrTerminalEndpoint,
        theme: BessieResolvedTerminalTheme = BessieThemeRegistry.definitions[.dark]!.resolvedTerminalTheme,
        performanceRecorder: BessiePerformanceRecorder = BessiePerformance.recorder,
        recordLocalUse: @escaping () -> Void = {},
        surfacePresented: @escaping () -> Void = {}
    ) {
        id = paneID
        self.surfacePresented = surfacePresented
        self.performanceRecorder = performanceRecorder
        self.recordLocalUse = recordLocalUse
        let localUseCallback = PaneLocalUseCallback(recordLocalUse)
        self.localUseCallback = localUseCallback
        ghosttyController = TerminalController(theme: theme.theme) { builder in
            builder.withBackgroundOpacity(1)
            // Herdr owns PTY mouse modes. Local libghostty must not encode mouse
            // sequences from a rendering-only surface — that desyncs capture state
            // and flooded new shells with SGR gibberish. Keep reporting off until a
            // negotiated public Herdr mouse-capture capability exists.
            builder.withCustom("mouse-reporting", "false")
            builder.withCustom("macos-option-as-alt", "left")
            builder.withCustom("mouse-hide-while-typing", "true")
            builder.withFontSize(13)
        }
        let bridge = PaneTerminalBridge()
        self.bridge = bridge
        let herdr = HerdrTerminalController(
            executablePath: endpoint.executablePath,
            paneID: paneID,
            socketPath: endpoint.socketPath,
            performanceRecorder: performanceRecorder,
            onFrame: { [weak bridge] bytes in bridge?.receive(bytes) },
            onState: { [weak bridge] state in bridge?.receive(state) }
        )
        herdrController = herdr
        let inputRouter = TerminalInputRouter(transport: herdr, performanceRecorder: performanceRecorder)
        self.inputRouter = inputRouter
        session = InMemoryTerminalSession(
            write: { [weak inputRouter] data in
                guard let inputRouter else { return }
                TerminalLocalUseForwarder.forward(
                    .raw(data),
                    recordLocalUse: localUseCallback.call,
                    enqueue: inputRouter.enqueue
                )
            },
            resize: { [weak herdr] viewport in
                herdr?.requestResize(
                    grid: TerminalGrid(columns: Int(viewport.columns), rows: Int(viewport.rows)),
                    cellWidthPixels: Int(viewport.cellWidthPixels),
                    cellHeightPixels: Int(viewport.cellHeightPixels)
                )
            }
        )
        bridge.session = session
        terminalView = BessieTerminalView(frame: .zero)
        terminalView.paneID = paneID
        terminalView.controller = ghosttyController
        terminalView.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        terminalView.sendOperation = { [weak self] operation in
            guard let self else { return }
            self.recordLocalUse()
            // Without a writable controller, mouse/keys are dead. Native Herdr TUI
            // commonly holds the exclusive attach; click-to-control must steal it.
            if case .ownershipConflict = self.status {
                BessieDiagnosticLog.append("Terminal pane=\(self.id) input while ownershipConflict — takeover")
                self.takeOver()
                return
            }
            if self.sessionMode == .observe {
                BessieDiagnosticLog.append("Terminal pane=\(self.id) input while observe — takeover")
                self.takeOver()
                return
            }
            TerminalLocalUseForwarder.forward(
                operation,
                recordLocalUse: {},
                enqueue: self.inputRouter.enqueue
            )
        }
        terminalView.recordLocalUse = { [weak self] in self?.recordLocalUse() }
        terminalView.delegate = self
        bridge.onState = { [weak self] state in self?.handle(state) }
        if ghosttyController.theme == theme.theme,
           ghosttyController.lastConfigurationIssue == nil {
            ghosttyController.setColorScheme(theme.scheme)
        }
        if ghosttyController.theme == theme.theme,
           ghosttyController.effectiveColorScheme == theme.scheme,
           ghosttyController.lastConfigurationIssue == nil {
            configuredTheme = theme
            terminalView.appearance = NSAppearance(named: theme.scheme == .light ? .aqua : .darkAqua)
        } else {
            recordThemeFailure()
        }
    }

    func release() {
        guard !released else { return }
        released = true
        terminalView.removeFromSuperview()
        herdrController.release()
    }
    func observe() { sessionMode = .observe; herdrController.observe() }
    func takeOver() { sessionMode = .takeover; herdrController.takeOver() }

    /// Gate synthesized mouse SGR. Plain shells stay `.unavailable` so pointer
    /// motion never becomes PTY gibberish; Hermes TUI panes get `.full`.
    func updateMouseCapture(agent: String?, foregroundCWD: String?) {
        terminalView.setMouseCaptureCapability(
            TerminalMouseRouting.captureCapability(agent: agent, foregroundCWD: foregroundCWD)
        )
    }
    func retry() { herdrController.retry() }
    func setPrewarming(_ prewarming: Bool) {
        guard isPrewarming != prewarming else { return }
        isPrewarming = prewarming
        if !prewarming, case .ownershipConflict = status {
            takeOver()
        }
    }
    func reconnectForVerification() { herdrController.reconnect(reason: "verification requested controller reconnect") }

    var acceptsInput: Bool {
        themeConfigurationError == nil && sessionMode != .observe && status.isReady
    }

    var hasReadyFrame: Bool { themeConfigurationError == nil && status.isReady }
    var hasStartedStream: Bool { surfaceLifecycle.streamStarted }

    var isSurfacePresented: Bool {
        terminalView.window != nil
            && terminalView.superview is TerminalSurfaceHostView
            && terminalView.bounds.width > 0
            && terminalView.bounds.height > 0
    }

    func updateFontSize(_ fontSize: Double) {
        guard configuredFontSize != fontSize else { return }
        configuredFontSize = fontSize
        ghosttyController.setTerminalConfiguration(Self.terminalOverrides(fontSize: fontSize))
    }

    @discardableResult
    func updateTheme(_ candidate: BessieResolvedTerminalTheme) -> Bool {
        guard configuredTheme != candidate else { return true }
        let priorTheme = ghosttyController.theme
        let priorScheme = ghosttyController.effectiveColorScheme
        let priorConfiguredTheme = configuredTheme
        let priorStatus = status
        let priorConfigurationError = themeConfigurationError
        if priorTheme != candidate.theme {
            _ = ghosttyController.setTheme(candidate.theme)
        }

        ghosttyController.setColorScheme(candidate.scheme)
        // `setTheme(false)` can mean either an unchanged request or a rejected
        // configuration. The controller's requested value and diagnostic are the
        // authoritative distinction, not the boolean alone.
        guard ghosttyController.theme == candidate.theme,
              ghosttyController.effectiveColorScheme == candidate.scheme,
              ghosttyController.lastConfigurationIssue == nil
        else {
            _ = ghosttyController.setTheme(priorTheme)
            if ghosttyController.effectiveColorScheme != priorScheme { ghosttyController.setColorScheme(priorScheme) }
            if ghosttyController.theme == priorTheme,
               ghosttyController.lastConfigurationIssue != nil {
                // libghostty 1.3.2 retains the rejected diagnostic when the
                // requested theme never changed, and equal-theme reapplication
                // is a no-op. Revalidate the retained theme through a temporary,
                // imperceptibly distinct override, then restore exact overrides.
                ghosttyController.setTerminalConfiguration(Self.terminalOverrides(fontSize: configuredFontSize + 0.001))
                ghosttyController.setTerminalConfiguration(Self.terminalOverrides(fontSize: configuredFontSize))
            }
            if let priorConfiguredTheme,
               ghosttyController.theme == priorTheme,
               ghosttyController.effectiveColorScheme == priorScheme,
               ghosttyController.lastConfigurationIssue == nil {
                configuredTheme = priorConfiguredTheme
                themeConfigurationError = priorConfigurationError
                status = priorStatus
                terminalView.needsDisplay = true
                BessieDiagnosticLog.append("Terminal pane=\(id) candidate theme rejected; prior theme restored")
                return false
            }
            recordThemeFailure()
            return false
        }

        configuredTheme = candidate
        themeConfigurationError = nil
        terminalView.appearance = NSAppearance(named: candidate.scheme == .light ? .aqua : .darkAqua)
        terminalView.needsDisplay = true
        return true
    }

    private static func terminalOverrides(fontSize: Double) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackgroundOpacity(1)
            builder.withCustom("mouse-reporting", "false")
            builder.withCustom("macos-option-as-alt", "left")
            builder.withCustom("mouse-hide-while-typing", "true")
            builder.withFontSize(Float(fontSize))
        }
    }

    private func recordThemeFailure() {
        let issue = ghosttyController.lastConfigurationIssue ?? "built-in terminal theme was rejected"
        themeConfigurationError = issue
        status = .failed("Terminal theme configuration failed")
        BessieDiagnosticLog.append("Terminal pane=\(id) theme configuration failed")
    }

    func attachTerminal(
        to host: TerminalSurfaceHostView,
        token: UUID,
        requestFocus: @escaping () -> Void,
        responderChanged: @escaping (Bool) -> Void
    ) {
        terminalView.attachmentToken = token
        terminalView.requestFocus = requestFocus
        terminalView.responderChanged = responderChanged
        if terminalView.superview !== host {
            let previousSuperview = terminalView.superview
            terminalView.removeFromSuperview()
            host.addSubview(terminalView)
            if !(previousSuperview is TerminalSurfaceHostView) {
                previousSuperview?.removeFromSuperview()
            }
        }
        // A reused SwiftUI host can retain a previous pane's terminal as a sibling
        // subview. Keep exactly one surface child so focus/refresh cannot paint under
        // a stale layer.
        for subview in host.subviews where subview !== terminalView {
            subview.removeFromSuperview()
        }
        terminalView.frame = host.bounds
    }

    func parkTerminal(from host: TerminalSurfaceHostView, token: UUID, in window: NSWindow?) {
        guard terminalView.attachmentToken == token, terminalView.superview === host else { return }
        if window?.firstResponder === terminalView { terminalView.responderChanged(false) }
        terminalView.requestFocus = {}
        terminalView.responderChanged = { _ in }
        // Keep the controller, libghostty view, and Herdr stream warm, but do not
        // leave hidden terminal views attached to the window. Attached offscreen
        // surfaces keep libghostty display links active and burn CPU while idle.
        terminalView.removeFromSuperview()
    }

    func terminalWasPresented(token: UUID) {
        guard terminalView.attachmentToken == token, isSurfacePresented else { return }
        surfacePresented()
        refreshAfterReattach(.full)
    }

    /// After tab/zen swaps park the surface, force a visible refresh so the
    /// pane does not stay blank/stale until the next Herdr frame happens to land.
    enum SurfaceRefresh: Equatable {
        /// Already-mounted same-tab focus: repaint only.
        case display
        /// Park/reattach or size change: fit + Herdr resize so frames refill.
        case full
    }

    func refreshAfterReattach(_ mode: SurfaceRefresh = .full) {
        terminalView.needsDisplay = true
        terminalView.updateGridFromStatus(status)
        guard mode == .full else { return }
        // Resume before fitToSize so the resize queued by the in-memory surface
        // follows retry on Herdr's serial controller queue.
        if case .failed = status {
            herdrController.retry()
        } else if case .stopped = status {
            herdrController.retry()
        }
        // fitToSize flows through InMemoryTerminalSession.resize, which already sends
        // the newly computed grid to Herdr. Do not follow it with another resize based
        // on status: status can still contain the old grid and cause resize oscillation.
        terminalView.fitToSize()
    }

    func makeTerminalFirstResponder(refresh: SurfaceRefresh = .display) {
        guard isSurfacePresented, terminalView.window?.isKeyWindow == true else {
            if isSurfacePresented { refreshAfterReattach(refresh) }
            return
        }
        terminalView.window?.makeFirstResponder(terminalView)
        refreshAfterReattach(refresh)
    }

    private func handle(_ state: TerminalControllerStatus) {
        guard themeConfigurationError == nil else { return }
        status = state
        terminalView.updateGridFromStatus(state)
        if case .ready = state, sessionMode == .takeover { sessionMode = .control }
        BessieDiagnosticLog.append("Terminal pane=\(id) state=\(state.diagnosticLabel)")
        // When another client holds exclusive control (usually native Herdr TUI
        // via mosh), auto-takeover so Bessie is writable. Without this the pane
        // shows an overlay and Hermes mouse never reaches the PTY.
        if case .ownershipConflict = state, !released, !isPrewarming {
            let now = ProcessInfo.processInfo.systemUptime
            // Debounce so two clients cannot thrash takeover forever.
            if now - lastAutoTakeoverAt >= 1.5 {
                lastAutoTakeoverAt = now
                BessieDiagnosticLog.append("Terminal pane=\(id) auto-takeover after ownership conflict")
                takeOver()
            }
            return
        }
        if case .ready(let grid, _, let full) = state,
           full,
           grid == resizePerformanceTarget,
           let sequence = resizePerformanceSequence {
            resizePerformanceSequence = nil
            resizePerformanceTarget = nil
            performanceRecorder.mark(.terminalResizeConverged, sequence: sequence)
            try? performanceRecorder.flushEvidence()
            BessieDiagnosticLog.append("Performance resize probe complete storms=40")
        }
        if case .ready = state,
           ProcessInfo.processInfo.environment["BESSIE_TERMINAL_PERFORMANCE_PROBE"] == "1",
           ProcessInfo.processInfo.environment["BESSIE_TERMINAL_PERFORMANCE_PANE_ID"] == id,
           !performanceProbeStarted,
           TerminalPerformanceProbeClaim.take() {
            performanceProbeStarted = true
            TerminalPerformanceProbe.run(
                session: session,
                inputRouter: inputRouter,
                recorder: performanceRecorder,
                completion: { [weak self] in
                    DispatchQueue.main.async { self?.runResizePerformanceProbe() }
                }
            )
        }
        guard case .ready = state,
              ProcessInfo.processInfo.environment["BESSIE_TERMINAL_LIVE_AUTOMATION"] == "1",
              !automationStarted
        else { return }
        automationStarted = true
        let token = id.replacingOccurrences(of: ":", with: "_")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            inputRouter.enqueue(.raw(Data("printf 'RAW_\(token)_牛é🐄'".utf8)))
            inputRouter.enqueue(.keys(["enter"]))
            inputRouter.enqueue(.paste("printf 'PASTE_\(token)'"))
            inputRouter.enqueue(.keys(["enter"]))
            BessieDiagnosticLog.append("Terminal pane=\(id) input=raw_unicode,special_enter,paste")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                let text = session.readViewportText() ?? ""
                let raw = text.contains("RAW_\(token)")
                let paste = text.contains("PASTE_\(token)")
                BessieDiagnosticLog.append("Terminal pane=\(id) viewport raw=\(raw) paste=\(paste) chars=\(text.count)")
                let command = "stty -echo -icanon min 1 time 0; b=$(dd bs=1 count=1 2>/dev/null | od -An -tu1 | tr -d ' '); stty sane; printf '\\nBESSIE_SHORTCUT_BYTE_%s\\n' \"$b\""
                inputRouter.enqueue(.paste(command))
                inputRouter.enqueue(.keys(["enter"]))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    terminalView.performBessieShortcut(.sendBytes(Data([0x02])))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        let shortcut = session.readViewportText()?.contains("BESSIE_SHORTCUT_BYTE_2") == true
                        BessieDiagnosticLog.append("Terminal pane=\(id) input=shortcut_cmd_b_control_b value=\(shortcut)")
                        inputRouter.enqueue(.raw(Data("printf '\\n'; seq 1 80".utf8)))
                        inputRouter.enqueue(.keys(["enter"]))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            guard let self else { return }
                            inputRouter.enqueue(.scroll(direction: .up, lines: 3, source: .wheel, column: nil, row: nil, modifiers: 0))
                            BessieDiagnosticLog.append("Terminal pane=\(id) input=scroll")
                        }
                    }
                }
            }
        }
    }

    private func runResizePerformanceProbe() {
        guard ProcessInfo.processInfo.environment["BESSIE_TERMINAL_PERFORMANCE_PROBE"] == "1",
              resizePerformanceSequence == nil,
              case .ready(let currentGrid, _, _) = status
        else { return }

        let alternateGrid = TerminalGrid(
            columns: max(2, currentGrid.columns - 1),
            rows: max(2, currentGrid.rows - 1)
        )
        let finalGrid = TerminalGrid(
            columns: currentGrid.columns + 1,
            rows: currentGrid.rows + 1
        )
        for index in 0..<39 {
            herdrController.requestResize(
                grid: index.isMultiple(of: 2) ? alternateGrid : currentGrid,
                cellWidthPixels: 8,
                cellHeightPixels: 16
            )
        }
        let sequence = performanceRecorder.nextSequence()
        resizePerformanceSequence = sequence
        resizePerformanceTarget = finalGrid
        performanceRecorder.mark(.terminalResizeRequested, sequence: sequence)
        herdrController.requestResize(
            grid: finalGrid,
            cellWidthPixels: 8,
            cellHeightPixels: 16
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard self?.resizePerformanceSequence == sequence else { return }
            BessieDiagnosticLog.append("Performance resize probe failed stage=convergence")
        }
    }

}

extension PaneTerminalController: TerminalSurfaceLifecycleDelegate {
    func terminalDidAttachSurface(_ surface: TerminalSurface) {
        guard !released else { return }
        if surfaceLifecycle.attach() == .startStream {
            herdrController.start()
        }
    }

    func terminalDidDetachSurface() {
        if !released { surfaceLifecycle.detach() }
    }
}

private enum TerminalPerformanceProbeClaim {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var claimed = false

    static func take() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}

private enum TerminalPerformanceProbe {
    private static let echoSampleCount = 200
    private static let outputSampleCount = 5
    private static let continuousInputSampleCount = 100

    static func run(
        session: InMemoryTerminalSession,
        inputRouter: TerminalInputRouter,
        recorder: BessiePerformanceRecorder,
        completion: @escaping @Sendable () -> Void
    ) {
        Task.detached {
            do {
                try measureEcho(session: session, inputRouter: inputRouter, recorder: recorder)
                try measureOutput(session: session, inputRouter: inputRouter, recorder: recorder)
                try runContinuousOutput(session: session, inputRouter: inputRouter, recorder: recorder)
                try recorder.flushEvidence()
                BessieDiagnosticLog.append(
                    "Performance terminal probe complete echo_samples=\(echoSampleCount) megabyte_runs=\(outputSampleCount) line_runs=\(outputSampleCount) continuous_seconds=300 continuous_input_samples=\(continuousInputSampleCount)"
                )
                completion()
            } catch {
                BessieDiagnosticLog.append(
                    "Performance terminal probe failed stage=terminal_workload error=\(error.localizedDescription)"
                )
            }
        }
    }

    private static func measureEcho(
        session: InMemoryTerminalSession,
        inputRouter: TerminalInputRouter,
        recorder: BessiePerformanceRecorder
    ) throws {
        try inputRouter.send(.raw(Data([0x15])))
        for index in 0..<echoSampleCount {
            let before = session.readViewportText()
            let byte = UInt8(97 + index % 26)
            guard let sequence = try inputRouter.send(
                .raw(Data([byte])),
                correlateToRenderedFrame: true
            ) else { throw HerdrClientError.unexpectedResponse("performance sequence unavailable") }
            guard waitUntil(upTo: 1, condition: { session.readViewportText() != before }) else {
                throw HerdrClientError.unexpectedResponse("printable echo did not become visible")
            }
            recorder.mark(.terminalFrameRendered, sequence: sequence)
            // Sample distinct key-to-visible-echo interactions at a fast typing
            // cadence instead of turning the latency probe into a saturation test.
            Thread.sleep(forTimeInterval: 0.03)
        }
        try inputRouter.send(.raw(Data([0x15])))
    }

    private static func measureOutput(
        session: InMemoryTerminalSession,
        inputRouter: TerminalInputRouter,
        recorder: BessiePerformanceRecorder
    ) throws {
        for index in 0..<outputSampleCount {
            let marker = "BESSIE_PERF_MEGABYTE_\(index)"
            let command = "python3 -c \"import sys;sys.stdout.write(('x'*79+'\\n')*13108+''.join(map(chr,[\(asciiList(marker))]))+'\\n');sys.stdout.flush()\""
            let sequence = recorder.nextSequence()
            recorder.mark(.terminalOutputMegabyteStarted, sequence: sequence)
            try submit(command, inputRouter: inputRouter)
            guard waitUntil(upTo: 10, condition: {
                session.readViewportText()?.contains(marker) == true
            }) else {
                throw HerdrClientError.unexpectedResponse("megabyte marker did not become visible")
            }
            recorder.mark(.terminalOutputMegabyteVisible, sequence: sequence)
            try inputRouter.send(.raw(Data([0x0c])))
            Thread.sleep(forTimeInterval: 0.2)
        }

        for index in 0..<outputSampleCount {
            let marker = "BESSIE_PERF_LINES_\(index)"
            let command = "python3 -c \"import sys;sys.stdout.write('x\\n'*50000+''.join(map(chr,[\(asciiList(marker))]))+'\\n');sys.stdout.flush()\""
            let sequence = recorder.nextSequence()
            recorder.mark(.terminalOutputLinesStarted, sequence: sequence)
            try submit(command, inputRouter: inputRouter)
            guard waitUntil(upTo: 15, condition: {
                session.readViewportText()?.contains(marker) == true
            }) else {
                throw HerdrClientError.unexpectedResponse("line marker did not become visible")
            }
            recorder.mark(.terminalOutputLinesVisible, sequence: sequence)
            try inputRouter.send(.raw(Data([0x0c])))
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func runContinuousOutput(
        session: InMemoryTerminalSession,
        inputRouter: TerminalInputRouter,
        recorder: BessiePerformanceRecorder
    ) throws {
        let marker = "BESSIE_PERF_CONTINUOUS_DONE"
        let command = "python3 -u -c \"import time;end=time.monotonic()+305;exec('while time.monotonic()<end:\\n print(120);time.sleep(.05)');print('\(marker)')\" &"
        let outputSequence = recorder.nextSequence()
        recorder.mark(.terminalContinuousOutputStarted, sequence: outputSequence)
        try submit(command, inputRouter: inputRouter)
        guard waitUntil(upTo: 2, condition: {
            session.readViewportText()?.contains("120") == true
        }) else {
            throw HerdrClientError.unexpectedResponse("continuous output did not start")
        }

        for index in 0..<continuousInputSampleCount {
            let inputMarker = "BESSIE_PERF_CONTINUOUS_INPUT_\(index)"
            let sequence = recorder.nextSequence()
            recorder.mark(.terminalContinuousInputStarted, sequence: sequence)
            try inputRouter.send(.raw(Data(inputMarker.utf8)))
            guard waitUntil(upTo: 1, condition: {
                guard let viewport = session.readViewportText() else { return false }
                let inputCharacters = viewport
                    .replacingOccurrences(of: "120", with: "")
                    .filter { !$0.isWhitespace }
                return inputCharacters.contains(inputMarker)
            }) else {
                throw HerdrClientError.unexpectedResponse("continuous output input marker did not become visible")
            }
            recorder.mark(.terminalContinuousInputVisible, sequence: sequence)
            try inputRouter.send(.raw(Data([0x15])))
            Thread.sleep(forTimeInterval: 0.5)
        }

        guard waitUntil(upTo: 360, pollInterval: 0.01, condition: {
            session.readViewportText()?.contains(marker) == true
        }) else {
            throw HerdrClientError.unexpectedResponse("continuous output marker did not become visible")
        }
        recorder.mark(.terminalContinuousOutputVisible, sequence: outputSequence)
    }

    private static func submit(_ command: String, inputRouter: TerminalInputRouter) throws {
        try inputRouter.send(.paste(command))
        try inputRouter.send(.keys(["enter"]))
    }

    private static func asciiList(_ value: String) -> String {
        value.utf8.map(String.init).joined(separator: ",")
    }

    private static func waitUntil(
        upTo timeout: TimeInterval,
        pollInterval: TimeInterval = 0.0005,
        condition: () -> Bool
    ) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }
}

private extension TerminalControllerStatus {
    var isReady: Bool {
        if case .ready = self { return true }
        return false
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
    var requestFocus: () -> Void = {}
    var responderChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> TerminalSurfaceHostView {
        let host = TerminalSurfaceHostView(frame: .zero)
        host.attach(
            controller: controller,
            fontSize: fontSize,
            requestFocus: requestFocus,
            responderChanged: responderChanged
        )
        return host
    }

    func updateNSView(_ host: TerminalSurfaceHostView, context: Context) {
        host.attach(
            controller: controller,
            fontSize: fontSize,
            requestFocus: requestFocus,
            responderChanged: responderChanged
        )
    }

    static func dismantleNSView(_ host: TerminalSurfaceHostView, coordinator: ()) {
        host.detach()
    }
}

final class PaneLocalUseCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: () -> Void

    init(_ callback: @escaping () -> Void) { self.callback = callback }

    func update(_ callback: @escaping () -> Void) {
        lock.withLock { self.callback = callback }
    }

    func call() {
        let current: () -> Void = lock.withLock { self.callback }
        if Thread.isMainThread {
            current()
        } else {
            DispatchQueue.main.async {
                current()
            }
        }
    }
}

@MainActor
final class TerminalSurfaceHostView: NSView {
    private(set) weak var paneController: PaneTerminalController?
    private(set) var attachmentToken = UUID()
    private(set) var presentationTracker = TerminalSurfacePresentationTracker()

    func attach(
        controller: PaneTerminalController,
        fontSize: Double,
        requestFocus: @escaping () -> Void,
        responderChanged: @escaping (Bool) -> Void
    ) {
        if let previous = paneController, previous !== controller {
            // SwiftUI reuses this host across pane/tab identity changes. Park the prior
            // controller before rebinding so its terminal leaves the view hierarchy and
            // cannot stay stuck on screen under/over the next pane.
            if window?.firstResponder === previous.terminalView {
                window?.makeFirstResponder(nil)
            }
            previous.parkTerminal(from: self, token: attachmentToken, in: window)
            attachmentToken = UUID()
            presentationTracker.reset()
        } else if paneController !== controller {
            attachmentToken = UUID()
            presentationTracker.reset()
        }
        paneController = controller
        guard controller.themeConfigurationError == nil else {
            for subview in subviews { subview.removeFromSuperview() }
            return
        }
        controller.updateFontSize(fontSize)
        controller.attachTerminal(
            to: self,
            token: attachmentToken,
            requestFocus: requestFocus,
            responderChanged: responderChanged
        )
        needsLayout = true
        if window != nil, bounds.width > 0, bounds.height > 0 {
            layout()
        }
    }

    override func layout() {
        super.layout()
        guard let controller = paneController,
              controller.terminalView.attachmentToken == attachmentToken,
              controller.terminalView.superview === self
        else { return }
        controller.terminalView.frame = bounds
        if window != nil, bounds.width > 0, bounds.height > 0 {
            controller.terminalView.responderChanged(window?.firstResponder === controller.terminalView)
            if presentationTracker.requiresFullPresentation(
                attachmentToken: attachmentToken,
                width: bounds.width,
                height: bounds.height
            ) {
                controller.terminalWasPresented(token: attachmentToken)
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let controller = paneController {
            controller.parkTerminal(from: self, token: attachmentToken, in: window)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func detach() {
        guard let controller = paneController else { return }
        if window?.firstResponder === controller.terminalView {
            window?.makeFirstResponder(nil)
        }
        controller.parkTerminal(from: self, token: attachmentToken, in: window)
        paneController = nil
        presentationTracker.reset()
    }
}

@MainActor
final class BessieTerminalView: TerminalView {
    var sendOperation: ((TerminalInputOperation) -> Void)?
    var recordLocalUse: () -> Void = {}
    /// Herdr/Bessie pane focus. Must be cheap when the pane is already active —
    /// a full `pane.focus` navigate on every click breaks mouse TUIs.
    var requestFocus: () -> Void = {}
    var responderChanged: (Bool) -> Void = { _ in }
    var attachmentToken = UUID()
    /// Optional pane id for diagnostics.
    var paneID: String = ""
    /// Mouse SGR is off by default (shells must stay quiet). Hermes panes opt in
    /// to `.full` via `PaneTerminalController.updateMouseCapture`.
    var mouseCaptureCapability: TerminalMouseCaptureCapability = .unavailable
    private var gridColumns = 80
    private var gridRows = 24
    private var heldButton: TerminalSGRMouse.Button?
    /// True once buttonDown chose the SGR path for this gesture.
    private var sgrGestureArmed = false
    private var lastMotionCell: (column: Int, row: Int)?
    private var mouseMonitor: Any?

    func setMouseCaptureCapability(_ capability: TerminalMouseCaptureCapability) {
        guard mouseCaptureCapability != capability else { return }
        mouseCaptureCapability = capability
        sgrGestureArmed = false
        lastMotionCell = nil
        BessieDiagnosticLog.append("Terminal pane=\(paneID) mouse capture=\(capability)")
        updateTrackingAreas()
    }

    func updateGridFromStatus(_ status: TerminalControllerStatus) {
        if case .ready(let grid, _, _) = status {
            gridColumns = max(1, grid.columns)
            gridRows = max(1, grid.rows)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func installMouseMonitorIfNeeded() {
        if mouseMonitor != nil { return }
        // SwiftUI hosting can steal hit-testing from the nested NSView so
        // mouseDown never arrives. A local monitor still sees the events when
        // the cursor is over this terminal's bounds.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .scrollWheel, .mouseMoved,
            ]
        ) { [weak self] event in
            guard let self, self.window != nil, event.window === self.window else { return event }
            // Only the topmost attached terminal under the cursor may handle the
            // event. Warm/prewarmed or stacked SwiftUI surfaces can share bounds;
            // without this every surface injects SGR into its own pane.
            guard self.isTopmostTerminalUnderMouse(event) else { return event }
            let local = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(local), self.bounds.width > 1, self.bounds.height > 1 else {
                return event
            }
            self.handleMonitoredMouse(event)
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                 .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                 .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                 .scrollWheel:
                return nil
            default:
                return event
            }
        }
    }

    private func isTopmostTerminalUnderMouse(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        // locationInWindow is in window base coords; hitTest expects superview coords.
        let pointInContent = content.convert(event.locationInWindow, from: nil)
        guard let hit = content.hitTest(pointInContent) else { return false }
        var view: NSView? = hit
        while let current = view {
            if current === self { return true }
            // Another Bessie terminal is above us.
            if current is BessieTerminalView { return false }
            view = current.superview
        }
        return false
    }

    private func handleMonitoredMouse(_ event: NSEvent) {
        BessieDiagnosticLog.append(
            "Terminal mouse event type=\(event.type.rawValue) bounds=\(Int(bounds.width))x\(Int(bounds.height)) grid=\(gridColumns)x\(gridRows)"
        )
        switch event.type {
        case .leftMouseDown:
            recordLocalUse()
            heldButton = .left
            handlePointer(kind: .buttonDown, button: .left, pressed: true, event: event) {
                super.mouseDown(with: event)
            }
        case .leftMouseDragged:
            handlePointer(kind: .drag, button: .left, pressed: true, event: event) {
                super.mouseDragged(with: event)
            }
        case .leftMouseUp:
            handlePointer(kind: .buttonUp, button: .left, pressed: false, event: event) {
                super.mouseUp(with: event)
            }
            heldButton = nil
            sgrGestureArmed = false
        case .rightMouseDown:
            recordLocalUse()
            heldButton = .right
            handlePointer(kind: .buttonDown, button: .right, pressed: true, event: event) {
                super.rightMouseDown(with: event)
            }
        case .rightMouseDragged:
            handlePointer(kind: .drag, button: .right, pressed: true, event: event) {
                super.rightMouseDragged(with: event)
            }
        case .rightMouseUp:
            handlePointer(kind: .buttonUp, button: .right, pressed: false, event: event) {
                super.rightMouseUp(with: event)
            }
            heldButton = nil
            sgrGestureArmed = false
        case .otherMouseDown:
            recordLocalUse()
            heldButton = .middle
            handlePointer(kind: .buttonDown, button: .middle, pressed: true, event: event) {
                super.otherMouseDown(with: event)
            }
        case .otherMouseDragged:
            handlePointer(kind: .drag, button: .middle, pressed: true, event: event) {
                super.otherMouseDragged(with: event)
            }
        case .otherMouseUp:
            handlePointer(kind: .buttonUp, button: .middle, pressed: false, event: event) {
                super.otherMouseUp(with: event)
            }
            heldButton = nil
            sgrGestureArmed = false
        case .mouseMoved:
            handlePointer(kind: .motion, button: heldButton, pressed: false, event: event) {
                super.mouseMoved(with: event)
            }
        case .scrollWheel:
            handlePointer(kind: .wheel, button: nil, pressed: false, event: event) {
                super.scrollWheel(with: event)
            }
        default:
            break
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        // Hover tracking only when this pane is allowed to synthesize SGR
        // (Hermes). Plain shells must not arm mouseMoved at all.
        if mouseCaptureCapability == .full {
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect, .enabledDuringMouseDrag],
                owner: self,
                userInfo: nil
            ))
        }
        installMouseMonitorIfNeeded()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { responderChanged(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            sgrGestureArmed = false
            heldButton = nil
            lastMotionCell = nil
            responderChanged(false)
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 116 || event.keyCode == 121 {
            sendOperation?(.scroll(direction: event.keyCode == 116 ? .up : .down, lines: 1, source: .pageKey, column: nil, row: nil, modifiers: 0))
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Never deliver Command chords into libghostty keyDown. Menu equivalents
        // (⌘Q quit, ⌘H hide, ⌘M minimize, …) and Bessie terminal Command shortcuts
        // are owned by performKeyEquivalent / the local shortcut monitor.
        if flags.contains(.command) {
            return
        }
        // Plain backspace/enter/tab/arrows must stay on the libghostty → raw write
        // path. Routing them through Herdr .keys is an RPC per key and feels laggy.
        if let combo = Self.herdrKeyCombo(event) {
            sendOperation?(.keys([combo]))
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        switch BessieKeyboardShortcutRouter.policy(
            for: BessieKeyboardShortcutCoordinator.stroke(for: event)
        ) {
        case .terminalShortcut(let action):
            return performBessieShortcut(action)
        case .appCommand:
            // Product commands are handled by the local monitor / menus.
            return false
        case .passthrough:
            // Critical: do not call super for passthrough Command chords.
            // libghostty has historically swallowed ⌘Q/H/M before the Quit menu.
            return false
        }
    }

    @discardableResult
    func performBessieShortcut(_ action: BessieTerminalShortcutAction) -> Bool {
        switch action {
        case .sendBytes(let data):
            guard sendOperation != nil else { return false }
            sendOperation?(.raw(data))
        case .copyOrSendInterrupt:
            if copySelectedTextToPasteboard() { return true }
            guard sendOperation != nil else { return false }
            sendOperation?(.raw(Data([0x03])))
        case .paste:
            guard let text = NSPasteboard.general.string(forType: .string), sendOperation != nil else { return false }
            sendOperation?(.paste(text))
        case .clearScrollback:
            return performBindingAction("clear_screen")
        case .selectAll:
            return performBindingAction("select_all")
        case .selectPreviousCommandOutput:
            // libghostty 1.3.2 exposes no surface action for semantic output
            // selection. Do not substitute select_all or reach into private C APIs.
            return false
        case .jumpToPrompt(let offset):
            guard let value = Int16(exactly: offset) else { return false }
            return jumpToPrompt(by: value)
        }
        return true
    }

    // MARK: - Mouse
    //
    // Ghostty owns PTY mouse mode. Bessie cannot see DECSET from Herdr frames, so
    // it synthesizes SGR for Hermes-grade TUIs (1000/1002/1003/1006). Free motion
    // is cell-throttled. Shift keeps local selection via super.

    override func mouseDown(with event: NSEvent) {
        recordLocalUse()
        heldButton = .left
        handlePointer(kind: .buttonDown, button: .left, pressed: true, event: event) {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointer(kind: .drag, button: .left, pressed: true, event: event) {
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        handlePointer(kind: .buttonUp, button: .left, pressed: false, event: event) {
            super.mouseUp(with: event)
        }
        heldButton = nil
        sgrGestureArmed = false
    }

    override func rightMouseDown(with event: NSEvent) {
        recordLocalUse()
        heldButton = .right
        handlePointer(kind: .buttonDown, button: .right, pressed: true, event: event) {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        handlePointer(kind: .drag, button: .right, pressed: true, event: event) {
            super.rightMouseDragged(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        handlePointer(kind: .buttonUp, button: .right, pressed: false, event: event) {
            super.rightMouseUp(with: event)
        }
        heldButton = nil
        sgrGestureArmed = false
    }

    override func otherMouseDown(with event: NSEvent) {
        recordLocalUse()
        heldButton = .middle
        handlePointer(kind: .buttonDown, button: .middle, pressed: true, event: event) {
            super.otherMouseDown(with: event)
        }
    }

    override func otherMouseDragged(with event: NSEvent) {
        handlePointer(kind: .drag, button: .middle, pressed: true, event: event) {
            super.otherMouseDragged(with: event)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        handlePointer(kind: .buttonUp, button: .middle, pressed: false, event: event) {
            super.otherMouseUp(with: event)
        }
        heldButton = nil
        sgrGestureArmed = false
    }

    override func mouseMoved(with event: NSEvent) {
        handlePointer(kind: .motion, button: heldButton, pressed: false, event: event) {
            super.mouseMoved(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        handlePointer(kind: .wheel, button: nil, pressed: false, event: event) {
            super.scrollWheel(with: event)
        }
    }

    private func handlePointer(
        kind: TerminalPointerKind,
        button: TerminalSGRMouse.Button?,
        pressed: Bool,
        event: NSEvent,
        localSelection: () -> Void
    ) {
        let forceLocal = event.modifierFlags.contains(.shift)
        let currentCell = cell(from: event)

        // Shift always forces local selection.
        if forceLocal {
            switch kind {
            case .buttonDown, .buttonUp, .drag:
                sgrGestureArmed = false
                ensureKeyFocus()
                localSelection()
            case .motion:
                break
            case .wheel:
                sendHerdrScroll(event)
            }
            return
        }

        // Unavailable: selection + herdr scroll only.
        if mouseCaptureCapability == .unavailable {
            switch kind {
            case .buttonDown:
                ensureKeyFocus()
                requestFocus()
                localSelection()
            case .buttonUp, .drag:
                localSelection()
            case .motion:
                break
            case .wheel:
                sendHerdrScroll(event)
            }
            return
        }

        // Buttons policy: no free motion.
        if mouseCaptureCapability == .buttons, kind == .motion {
            return
        }

        // Full / buttons: synthesize SGR when we can encode a cell.
        if kind == .motion {
            // Cell-throttle free hover.
            if let currentCell {
                if let last = lastMotionCell,
                   last.column == currentCell.column,
                   last.row == currentCell.row {
                    return
                }
                lastMotionCell = currentCell
            }
        } else if kind == .buttonDown || kind == .drag, let currentCell {
            lastMotionCell = currentCell
        }

        if kind == .buttonUp || kind == .drag {
            // Stay on SGR only if the gesture armed at buttonDown.
            if !sgrGestureArmed, mouseCaptureCapability == .buttons {
                localSelection()
                if kind == .buttonUp {
                    heldButton = nil
                }
                return
            }
        }

        if let data = encodeSGR(kind: kind, button: button, pressed: pressed, event: event) {
            BessieDiagnosticLog.append(
                "Terminal pane=\(paneID) SGR ok kind=\(kind) bytes=\(data.count) capture=\(mouseCaptureCapability) cell=\(String(describing: currentCell))"
            )
            if kind == .buttonDown {
                sgrGestureArmed = true
                ensureKeyFocus()
            }
            sendOperation?(.raw(data))
            return
        }

        // Encode failed — fall back.
        if kind == .buttonDown || kind == .wheel {
            BessieDiagnosticLog.append(
                "Terminal pane=\(paneID) SGR fail kind=\(kind) capture=\(mouseCaptureCapability) cell=\(String(describing: currentCell))"
            )
        }
        switch kind {
        case .buttonDown:
            ensureKeyFocus()
            requestFocus()
            localSelection()
        case .buttonUp, .drag:
            localSelection()
        case .wheel:
            sendHerdrScroll(event)
        case .motion:
            break
        }
    }

    private func sendHerdrScroll(_ event: NSEvent) {
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return }
        let lines = max(1, Int(abs(dy) / 8))
        sendOperation?(.scroll(
            direction: dy > 0 ? .up : .down,
            lines: lines,
            source: .wheel,
            column: nil,
            row: nil,
            modifiers: 0
        ))
    }

    private func ensureKeyFocus() {
        guard window?.firstResponder !== self else { return }
        window?.makeFirstResponder(self)
    }

    private func encodeSGR(
        kind: TerminalPointerKind,
        button: TerminalSGRMouse.Button?,
        pressed: Bool,
        event: NSEvent
    ) -> Data? {
        guard let cell = cell(from: event) else {
            BessieDiagnosticLog.append("Terminal mouse encode nil cell")
            return nil
        }
        let flags = event.modifierFlags
        switch kind {
        case .buttonDown, .buttonUp:
            guard let button else {
                BessieDiagnosticLog.append("Terminal mouse encode nil button")
                return nil
            }
            return TerminalSGRMouse.button(
                button,
                pressed: pressed,
                column: cell.column,
                row: cell.row,
                control: flags.contains(.control),
                shift: flags.contains(.shift),
                meta: flags.contains(.option)
            )
        case .drag:
            return TerminalSGRMouse.motion(
                buttonHeld: heldButton ?? button,
                column: cell.column,
                row: cell.row,
                control: flags.contains(.control),
                shift: flags.contains(.shift),
                meta: flags.contains(.option)
            )
        case .motion:
            return TerminalSGRMouse.motion(
                buttonHeld: heldButton,
                column: cell.column,
                row: cell.row,
                control: flags.contains(.control),
                shift: flags.contains(.shift),
                meta: flags.contains(.option)
            )
        case .wheel:
            let dy = event.scrollingDeltaY
            let dx = event.scrollingDeltaX
            guard dy != 0 || dx != 0 else { return nil }
            let wheelButton: TerminalSGRMouse.Button
            if abs(dy) >= abs(dx) {
                wheelButton = dy > 0 ? .wheelUp : .wheelDown
            } else {
                wheelButton = dx > 0 ? .wheelRight : .wheelLeft
            }
            return TerminalSGRMouse.button(
                wheelButton,
                pressed: true,
                column: cell.column,
                row: cell.row,
                control: flags.contains(.control),
                shift: flags.contains(.shift),
                meta: flags.contains(.option)
            )
        }
    }

    private func mousePoint(from event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func cell(from event: NSEvent) -> (column: Int, row: Int)? {
        let p = mousePoint(from: event)
        return TerminalSGRMouse.cell(
            x: p.x,
            y: p.y,
            width: bounds.width,
            height: bounds.height,
            columns: gridColumns,
            rows: gridRows
        )
    }

    private static func herdrKeyCombo(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasCommand = flags.contains(.command)
        // Command chords are handled by Bessie shortcuts / performKeyEquivalent.
        if hasCommand { return nil }

        let hasControl = flags.contains(.control)
        let hasOption = flags.contains(.option)
        let hasShift = flags.contains(.shift)

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
            if hasControl,
               let value = event.charactersIgnoringModifiers?.lowercased(), value.count == 1
            { base = value } else { base = nil }
        }
        guard let base else { return nil }

        // Unmodified editing keys: let libghostty emit raw bytes (fast local path).
        // Only route through Herdr keys when Control/Option/Shift change the meaning.
        let plainEditingKeys: Set<String> = [
            "left", "right", "up", "down", "enter", "tab", "backspace", "esc",
        ]
        if plainEditingKeys.contains(base), !hasControl, !hasOption, !(hasShift && base == "tab") {
            // shift+arrows still go local for selection when possible
            if hasShift, ["left", "right", "up", "down"].contains(base) {
                return nil
            }
            if !hasShift { return nil }
        }

        var modifiers: [String] = []
        if hasControl { modifiers.append("ctrl") }
        if hasOption { modifiers.append("alt") }
        if hasShift, base != "tab" { modifiers.append("shift") }
        if hasShift, base == "tab" { return "shift+tab" }
        return (modifiers + [base]).joined(separator: "+")
    }
}
