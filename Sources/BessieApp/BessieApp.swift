import AppKit
import BessieCore
import Combine
import Foundation
import GhosttyTerminal
import SwiftUI

enum BessieWindowPolicy {
    static let controllerSceneID = "main"
    static let maximumControllerWindowCount = 1
}

enum BessiePerformance {
    static let recorder: BessiePerformanceRecorder = {
        let recorder = BessiePerformanceRecorder.configured()
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        let launchUptime = NSRunningApplication.current.launchDate.map {
            uptime - max(0, now.timeIntervalSince($0))
        } ?? uptime
        recorder.markProcessStart(atSystemUptime: max(0, launchUptime))
        return recorder
    }()
}

private enum BessieStartupMainThreadProbe {
    private static let sampleCount = 25
    private static let lock = NSLock()
    nonisolated(unsafe) private static var claimed = false

    static func runIfRequested(recorder: BessiePerformanceRecorder) {
        guard ProcessInfo.processInfo.environment["BESSIE_STARTUP_PERFORMANCE_PROBE"] == "1",
              lock.withLock({
                  guard !claimed else { return false }
                  claimed = true
                  return true
              })
        else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<sampleCount {
                let sequence = recorder.nextSequence()
                let completed = DispatchSemaphore(value: 0)
                recorder.mark(.startupMainThreadProbeScheduled, sequence: sequence)
                DispatchQueue.main.async {
                    recorder.mark(.startupMainThreadProbeCompleted, sequence: sequence)
                    completed.signal()
                }
                guard completed.wait(timeout: .now() + 2) == .success else {
                    BessieDiagnosticLog.append("Performance startup probe failed stage=main_thread")
                    return
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
            try? recorder.flushEvidence()
            BessieDiagnosticLog.append("Performance startup probe complete main_thread_samples=\(sampleCount)")
        }
    }
}

extension Notification.Name {
    static let bessieCommand = Notification.Name("Bessie.command")
    static let bessieMainWindowWillClose = Notification.Name("Bessie.mainWindowWillClose")
}

@main
struct BessieApp: App {
    @NSApplicationDelegateAdaptor(BessieAppDelegate.self) private var appDelegate
    @StateObject private var settings: BessieSettingsModel
    @StateObject private var notifications: BessieNotificationCoordinator
    @StateObject private var fleet: ConnectionFleetViewModel
    @StateObject private var terminalRegistry: TerminalControllerRegistry
    @StateObject private var themeCoordinator: BessieThemeCoordinator
    private let featureFlags: BessieFeatureFlags

    init() {
        let recorder = BessiePerformance.recorder
        recorder.mark(.appStart)
        featureFlags = BessieFeatureFlags(environment: ProcessInfo.processInfo.environment)
        let settings = BessieSettingsModel()
        let terminalRegistry = TerminalControllerRegistry()
        _settings = StateObject(wrappedValue: settings)
        _notifications = StateObject(wrappedValue: BessieNotificationCoordinator())
        _fleet = StateObject(wrappedValue: ConnectionFleetViewModel(performanceRecorder: recorder))
        _terminalRegistry = StateObject(wrappedValue: terminalRegistry)
        _themeCoordinator = StateObject(wrappedValue: BessieThemeCoordinator(
            settings: settings,
            terminalRegistry: terminalRegistry,
            initialSystemScheme: Self.currentSystemScheme
        ))
    }

    var body: some Scene {
        Window("Bessie", id: BessieWindowPolicy.controllerSceneID) {
            BessieWindowRoot {
                ConnectView(
                    fleet: fleet,
                    featureFlags: featureFlags,
                    terminalRegistry: terminalRegistry,
                    initiallyShowsColdOpen: !Self.isOnboardingStepArtboard
                )
                    .onAppear { BessieAppIconController.apply(settings.preferences.appIcon) }
                    .onAppear {
                        BessiePerformance.recorder.mark(.firstWindowContent)
                        BessieStartupMainThreadProbe.runIfRequested(recorder: BessiePerformance.recorder)
                        Self.applyOnboardingArtboardAppearance(settings.preferences.appearance)
                    }
                    .onChange(of: settings.preferences.appIcon) { _, icon in
                        BessieAppIconController.apply(icon)
                    }
            }
                .overlay(alignment: .top) {
                    BessieWindowChromeRegion(action: .toggleFullScreen)
                        .frame(height: BessieDesign.titlebarHeight)
                        .ignoresSafeArea(edges: .top)
                }
                .background(BessieMainWindowProbe(coordinator: appDelegate.windowCoordinator))
                .background(BessieLifecycleInstaller(
                    appDelegate: appDelegate,
                    fleet: fleet,
                    settings: settings,
                    notifications: notifications
                ))
                .modifier(BessieThemeAppearanceIngress())
                .environmentObject(settings)
                .environmentObject(themeCoordinator)
                .environmentObject(notifications)
                .environment(\.bessieDensity, .metrics(for: settings.preferences.density))
                .preferredColorScheme(settings.preferences.appearance.preferredColorScheme)
                .frame(
                    minWidth: BessieAccessibilityContract.minimumContentWidth,
                    minHeight: ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "09"
                        ? 0
                        : BessieAccessibilityContract.minimumContentHeight
                )
                .task { fleet.startIntentServer() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    fleet.stopIntentServer()
                }
        }
        // Keep native window controls without AppKit's separate titlebar backing.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Bessie") { appDelegate.quitBessie() }
                    .keyboardShortcut("q", modifiers: .command)
            }
            CommandMenu("Bessie") {
                Button("Command Palette…") {
                    NotificationCenter.default.post(name: .bessieCommand, object: BessieShortcutCommand.showCommandPalette)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            CommandMenu("Zen") {
                Button("Toggle Zen") {
                    NotificationCenter.default.post(name: .bessieCommand, object: BessieShortcutCommand.toggleZen)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                Button("Exit Zen") {
                    NotificationCenter.default.post(name: .bessieCommand, object: BessieShortcutCommand.exitZen)
                }
                Divider()
                Button("Previous agent") {
                    NotificationCenter.default.post(name: .bessieCommand, object: BessieShortcutCommand.previousAgent)
                }
                .keyboardShortcut("[", modifiers: [.command, .option, .shift])
                Button("Next agent") {
                    NotificationCenter.default.post(name: .bessieCommand, object: BessieShortcutCommand.nextAgent)
                }
                .keyboardShortcut("]", modifiers: [.command, .option, .shift])
                Button("Next agent that needs you") {
                    NotificationCenter.default.post(name: .bessieCommand, object: BessieShortcutCommand.openNextNeedsYou)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        Settings {
            BessieWindowRoot {
                BessieSettingsView()
            }
                .modifier(BessieThemeAppearanceIngress())
                .environmentObject(settings)
                .environmentObject(themeCoordinator)
                .environmentObject(notifications)
                .environment(\.bessieDensity, .metrics(for: settings.preferences.density))
                .preferredColorScheme(settings.preferences.appearance.preferredColorScheme)
                .environmentObject(fleet)
        }
    }

    private static var isOnboardingStepArtboard: Bool {
        guard let artboard = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] else { return false }
        return (10...13).contains(Int(artboard) ?? 0)
    }

    private static var currentSystemScheme: ColorScheme {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
            ? .light
            : .dark
    }

    private static func applyOnboardingArtboardAppearance(_ appearance: BessieAppearance) {
        guard let artboard = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"],
              let artboardNumber = Int(artboard), (9...13).contains(artboardNumber)
        else { return }
        let scheme: ColorScheme
        if artboardNumber == 9 {
            scheme = .dark
        } else {
            scheme = BessieThemeRegistry.scheme(for: appearance, systemScheme: .dark)
        }
        NSApp.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        let background = NSColor(BessieThemeRegistry.definition(for: appearance, systemScheme: scheme).palette.background)
        NSApp.windows.forEach { $0.backgroundColor = background }
    }
}

private struct BessieLifecycleInstaller: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let appDelegate: BessieAppDelegate
    let fleet: ConnectionFleetViewModel
    let settings: BessieSettingsModel
    let notifications: BessieNotificationCoordinator

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            appDelegate.configure(
                fleet: fleet,
                settings: settings,
                notifications: notifications,
                openWindow: { openWindow(id: BessieWindowPolicy.controllerSceneID) },
                openSettings: { openSettings() }
            )
        }
    }
}

@MainActor
final class ConnectionViewModel: ObservableObject {
    @Published private(set) var presentation = ConnectPresentation.initial
    @Published private(set) var projection: HerdrSessionProjection?
    @Published private(set) var terminalEndpoint: HerdrTerminalEndpoint?
    @Published private(set) var agentCatalog = AgentCatalog(items: [])
    @Published private(set) var actionError: String?
    @Published private(set) var runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .runtimeResolution)
    @Published private(set) var actionInFlight = false
    @Published private(set) var navigationInFlight = false
    @Published private(set) var activeConnection: BessieConnectionDefinition = .localBessie
    @Published private(set) var projectMaterializationConnection: BessieProjectMaterializationConnection?
    @Published private(set) var remoteFileAccess: SSHRemoteFileAccess?
    private var connectionTask: Task<Void, Never>?
    private var connectionRunner: HerdrConnectionRunner?
    private var remoteBridge: RemoteHerdrBridge?
    private var connectionToken = UUID()
    private var actionClient: HerdrActionClient?
    private let intentDispatcher: BessieIntentActionDispatcher
    private var openPaneToken: UUID?
    private var navigationToken: UUID?
    private var catalogSocketPath: String?
    private var catalogLoadInFlight = false
    private var projectHandoffToken: UUID?
    @Published private(set) var catalogLoaded = false
    private let runtimeSelection: HerdrRuntimeSelection
    private let bundledRuntimeURL: URL?
    private let runtimeValidator: HerdrRuntimeValidator?
    private let bundledRuntimeLock: BundledRuntimeLock?
    private let performanceRecorder: BessiePerformanceRecorder
    private(set) var performanceSequence: UInt64?

    init(
        runtimeSelection: HerdrRuntimeSelection = .bundled,
        bundledRuntimeURL: URL? = nil,
        intentDispatcher: BessieIntentActionDispatcher = BessieIntentActionDispatcher(),
        performanceRecorder: BessiePerformanceRecorder = BessiePerformance.recorder
    ) {
        self.runtimeSelection = runtimeSelection
        self.bundledRuntimeURL = bundledRuntimeURL
        self.intentDispatcher = intentDispatcher
        self.performanceRecorder = performanceRecorder
        let validation = bundledRuntimeURL.map(Self.runtimeValidation(for:))
        runtimeValidator = validation?.validator
        bundledRuntimeLock = validation?.lock
    }

    func start(connection: BessieConnectionDefinition = .localBessie) {
        guard connectionTask == nil else { return }
        activeConnection = connection
        let performanceSequence = performanceRecorder.nextSequence()
        self.performanceSequence = performanceSequence
        performanceRecorder.mark(.connectionStart, sequence: performanceSequence)
        let token = UUID()
        connectionToken = token
        if let runToken = ProcessInfo.processInfo.environment["BESSIE_RUN_TOKEN"] {
            let processID = ProcessInfo.processInfo.processIdentifier
            BessieDiagnosticLog.append("App run=\(runToken) pid=\(processID)")
        }
        connectionTask = Task {
            var environment = ProcessInfo.processInfo.environment
            switch connection.kind {
            case .local:
                environment["BESSIE_HERDR_SESSION"] = connection.session ?? BessieCompatibility.sessionName
            case .ssh:
                do {
                    let bridge = try RemoteHerdrBridge(connection: connection)
                    self.remoteBridge = bridge
                    performanceRecorder.mark(.remoteBridgeStart, sequence: performanceSequence)
                    let socketPath = try await Task.detached { try bridge.start() }.value
                    performanceRecorder.mark(.remoteTunnelReady, sequence: performanceSequence)
                    guard !Task.isCancelled, self.connectionToken == token else { bridge.stop(); return }
                    self.remoteFileAccess = bridge.fileAccess
                    environment["BESSIE_HERDR_SOCKET_PATH"] = socketPath
                    environment["BESSIE_HERDR_AUTOSTART"] = "0"
                } catch {
                    guard self.connectionToken == token else { return }
                    self.remoteBridge?.stop()
                    self.remoteBridge = nil
                    self.remoteFileAccess = nil
                    self.presentation = ConnectPresentation(
                        title: "Couldn't connect to \(connection.name)",
                        detail: error.localizedDescription,
                        status: .lost
                    )
                    self.connectionTask = nil
                    return
                }
            }
            let runner = HerdrConnectionRunner(
                repositoryRoot: Self.repositoryRoot,
                environment: environment,
                runtimeSelection: runtimeSelection,
                bundledRuntimeURL: bundledRuntimeURL,
                validator: runtimeValidator,
                bundledRuntimeLock: bundledRuntimeLock,
                performanceRecorder: performanceRecorder,
                performanceSequence: performanceSequence
            )
            connectionRunner = runner
            await runner.run { [weak self] state in
                BessieDiagnosticLog.append(state.label)
                let projection: HerdrSessionProjection?
                let endpoint: HerdrTerminalEndpoint?
                if case .connected(let runtime, let socketPath, let snapshot) = state {
                    projection = try? HerdrSessionProjection(snapshot: snapshot)
                    endpoint = HerdrTerminalEndpoint(
                        connectionID: connection.id,
                        executablePath: runtime.url.path,
                        socketPath: socketPath
                    )
                    if let projection {
                        let labels = projection.workspaces.map(\.label).joined(separator: ",")
                        BessieDiagnosticLog.append("Snapshot workspace_labels=\(labels)")
                        BessieDiagnosticLog.append("Snapshot connection=\(connection.name) agents=\(projection.agents.count)")
                    }
                } else {
                    projection = nil
                    endpoint = nil
                }
                Task { @MainActor in
                    guard self?.connectionToken == token else { return }
                    if case .connected(_, let socketPath, let snapshot) = state {
                        let identity = HerdrServerIdentity(
                            version: snapshot.version,
                            protocolVersion: snapshot.protocolVersion
                        )
                        if self?.projectMaterializationConnection?.definition != connection
                            || self?.projectMaterializationConnection?.socketPath
                                != URL(fileURLWithPath: socketPath).standardizedFileURL.path
                            || self?.projectMaterializationConnection?.identity != identity
                        {
                            self?.projectMaterializationConnection = BessieProjectMaterializationConnection(
                                definition: connection,
                                socketPath: socketPath,
                                generation: UUID(),
                                identity: identity
                            )
                        }
                    } else {
                        self?.projectMaterializationConnection = nil
                        if self?.projectHandoffToken != nil {
                            self?.projectHandoffToken = nil
                            self?.actionInFlight = false
                        }
                    }
                    self?.recordDiagnostic(state)
                    self?.presentation = ConnectPresentation(connectionState: state)
                    self?.projection = projection
                    self?.terminalEndpoint = endpoint
                    if projection != nil {
                        self?.performanceRecorder.mark(.snapshotInstalled, sequence: performanceSequence)
                    }
                    self?.actionClient = endpoint.map { HerdrActionClient(api: HerdrSocketAPI(socketPath: $0.socketPath)) }
                    self?.intentDispatcher.update(
                        client: self?.actionClient,
                        connectionID: connection.id,
                        projection: projection
                    )
                    if let endpoint { self?.ensureAgentCatalog(socketPath: endpoint.socketPath) }
                }
            }
        }
    }

    func retry() {
        let connection = activeConnection
        stop()
        catalogLoaded = false
        presentation = .initial
        start(connection: connection)
    }

    func switchConnection(to connection: BessieConnectionDefinition) {
        guard connection.id != activeConnection.id || connectionTask == nil else { return }
        stop()
        projection = nil
        terminalEndpoint = nil
        actionClient = nil
        catalogSocketPath = nil
        catalogLoaded = false
        presentation = ConnectPresentation(
            title: "Connecting to \(connection.name)",
            detail: connection.detail,
            status: .connecting
        )
        start(connection: connection)
    }

    func stop() {
        connectionToken = UUID()
        openPaneToken = nil
        navigationToken = nil
        actionInFlight = false
        navigationInFlight = false
        connectionRunner?.cancel()
        connectionTask?.cancel()
        connectionTask = nil
        connectionRunner = nil
        remoteBridge?.stop()
        remoteBridge = nil
        remoteFileAccess = nil
        projection = nil
        terminalEndpoint = nil
        actionClient = nil
        intentDispatcher.update(client: nil, connectionID: activeConnection.id, projection: nil)
        catalogSocketPath = nil
        catalogLoaded = false
        agentCatalog = AgentCatalog(items: [])
        projectMaterializationConnection = nil
        performanceSequence = nil
    }

    func perform(
        _ action: HerdrAction,
        confirmDestructive: Bool = false,
        completion: (@MainActor (HerdrSessionProjection) -> Void)? = nil,
        failure: (@MainActor () -> Void)? = nil
    ) {
        let connectionGeneration = connectionToken
        let connectionID = activeConnection.id
        actionInFlight = true
        actionError = nil
        Task.detached {
            do {
                let projection = try self.intentDispatcher.perform(
                    [action],
                    connectionID: connectionID,
                    confirmDestructive: confirmDestructive
                )
                await MainActor.run {
                    guard self.connectionToken == connectionGeneration else { return }
                    self.projection = projection
                    self.actionInFlight = false
                    completion?(projection)
                }
            } catch {
                await MainActor.run {
                    guard self.connectionToken == connectionGeneration else { return }
                    self.actionInFlight = false
                    self.actionError = error.localizedDescription
                    failure?()
                }
            }
        }
    }

    func openPane(
        _ target: PaneOpenTarget,
        completion: (@MainActor (HerdrSessionProjection) -> Void)? = nil,
        failure: (@MainActor () -> Void)? = nil
    ) {
        let actions = (projection?.prunedNavigationActions([
            .workspaceFocus(id: target.workspaceID),
            .tabFocus(id: target.tabID),
            .paneFocus(id: target.paneID),
        ]) ?? [
            .workspaceFocus(id: target.workspaceID),
            .tabFocus(id: target.tabID),
            .paneFocus(id: target.paneID),
        ])
        if actions.isEmpty, let projection {
            completion?(projection)
            return
        }
        navigate(actions, completion: completion, failure: failure)
    }

    /// Focus changes are intentionally independent from mutation actions. The newest
    /// navigation request wins, so rapid sidebar/tab clicks never wait behind stale focus work.
    func navigate(
        _ actions: [HerdrAction],
        completion: (@MainActor (HerdrSessionProjection) -> Void)? = nil,
        failure: (@MainActor () -> Void)? = nil
    ) {
        let pruned = projection?.prunedNavigationActions(actions) ?? actions
        if pruned.isEmpty {
            if let projection { completion?(projection) }
            return
        }

        let connectionGeneration = connectionToken
        let connectionID = activeConnection.id
        let requestToken = UUID()
        let navigationStartedAt = ProcessInfo.processInfo.systemUptime
        openPaneToken = requestToken
        navigationToken = requestToken
        navigationInFlight = true
        actionError = nil

        // Paint local focus immediately so pane/tab chrome does not wait on Herdr RPC + snapshot.
        if let current = projection,
           let optimistic = try? current.applyingNavigationActions(pruned)
        {
            projection = optimistic
            intentDispatcher.installProjection(optimistic, connectionID: connectionID)
        }

        Task.detached {
            do {
                let projection = try self.intentDispatcher.perform(pruned, connectionID: connectionID)
                await MainActor.run {
                    guard self.connectionToken == connectionGeneration,
                          self.navigationToken == requestToken
                    else { return }
                    self.projection = projection
                    self.navigationInFlight = false
                    let elapsed = (ProcessInfo.processInfo.systemUptime - navigationStartedAt) * 1_000
                    BessieDiagnosticLog.append(String(
                        format: "Terminal switch stage=herdr_confirmed elapsed_ms=%.1f action_count=%d",
                        elapsed,
                        pruned.count
                    ))
                    completion?(projection)
                }
            } catch {
                await MainActor.run {
                    guard self.connectionToken == connectionGeneration,
                          self.navigationToken == requestToken
                    else { return }
                    self.navigationInFlight = false
                    self.actionError = error.localizedDescription
                    failure?()
                }
            }
        }
    }

    func openProjectHandoff(
        _ handoff: ProjectWorkspaceHandoff,
        completion: (@MainActor (HerdrSessionProjection) -> Void)? = nil
    ) {
        guard projectMaterializationConnection == handoff.connection,
              let handoffProjection = try? HerdrSessionProjection(snapshot: handoff.snapshot),
              handoffProjection.workspaces.contains(where: { $0.id == handoff.workspaceID }),
              handoff.tabID == nil || handoffProjection.tabs.contains(where: {
                  $0.id == handoff.tabID && $0.workspaceID == handoff.workspaceID
              }),
              handoff.paneID == nil || handoffProjection.panes.contains(where: {
                  $0.id == handoff.paneID && $0.workspaceID == handoff.workspaceID
                      && (handoff.tabID == nil || $0.tabID == handoff.tabID)
              })
        else { return }
        var actions: [HerdrAction] = [.workspaceFocus(id: handoff.workspaceID)]
        if let tabID = handoff.tabID { actions.append(.tabFocus(id: tabID)) }
        if let paneID = handoff.paneID { actions.append(.paneFocus(id: paneID)) }
        actionInFlight = true
        actionError = nil
        let handoffToken = UUID()
        projectHandoffToken = handoffToken
        let connectionID = activeConnection.id
        Task.detached {
            do {
                let projection = try self.intentDispatcher.perform(actions, connectionID: connectionID)
                await MainActor.run {
                    guard self.projectHandoffToken == handoffToken,
                          self.projectMaterializationConnection == handoff.connection
                    else { return }
                    self.projectHandoffToken = nil
                    self.projection = projection
                    self.actionInFlight = false
                    completion?(projection)
                }
            } catch {
                await MainActor.run {
                    guard self.projectHandoffToken == handoffToken,
                          self.projectMaterializationConnection == handoff.connection
                    else { return }
                    self.projectHandoffToken = nil
                    self.actionInFlight = false
                    self.actionError = error.localizedDescription
                }
            }
        }
    }

    func clearActionError() { actionError = nil }

    func markShellReady() {
        performanceRecorder.mark(.shellReady, sequence: performanceSequence)
    }

    func reportRouteFailure(_ message: String) {
        actionError = message
    }

    func updateTerminalDiagnostic(_ facts: TerminalControllerFacts) {
        runtimeDiagnostic.terminalControllerHealthy = facts.healthy
        if let finding = facts.finding {
            runtimeDiagnostic.stage = .terminalController
            runtimeDiagnostic.finding = finding
        } else if runtimeDiagnostic.apiHealthy, runtimeDiagnostic.finding == .terminalControlUnavailable {
            runtimeDiagnostic.stage = .workspaceReady
            runtimeDiagnostic.finding = nil
        }
    }

    private func recordDiagnostic(_ state: HerdrConnectionState) {
        switch state {
        case .notFound:
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .runtimeResolution, finding: .externalMissing)
        case .resolutionFailed(let failure):
            let finding: SetupFinding
            switch failure {
            case .bundledMissing, .bundledNotExecutable: finding = .bundledIntegrity
            case .systemMissing, .customMissing: finding = .externalMissing
            case .customNotExecutable: finding = .externalNotExecutable
            }
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(
                stage: .runtimeResolution,
                finding: finding,
                runtime: diagnosticRuntime(for: failure)
            )
        case .validationFailed(let runtime, let failure):
            let finding: SetupFinding
            switch failure {
            case .bundledIntegrity: finding = .bundledIntegrity
            case .externalMissing: finding = .externalMissing
            case .externalNotExecutable: finding = .externalNotExecutable
            case .incompatible: finding = .incompatible
            case .permission, .filesystem: finding = .permissionOrFilesystem
            }
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .runtimeValidation, finding: finding, runtime: runtime)
        case .stopped(let runtime, let socket):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .serverStatus, runtime: runtime, apiSocketPath: socket)
        case .starting(let runtime):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .serverStatus, runtime: runtime)
        case .startFailed(let runtime, _):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .serverStatus, finding: .serverStartup, runtime: runtime)
        case .incompatible(let runtime, let identity, _):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .runtimeValidation, finding: .incompatible, runtime: runtime,
                observedVersion: identity.version, observedProtocol: identity.protocolVersion)
        case .connecting(let runtime):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .apiConnection, runtime: runtime)
        case .apiUnavailable(let runtime, _):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .apiConnection, finding: .apiUnavailable, runtime: runtime)
        case .connected(let runtime, let socket, _):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .workspaceReady, runtime: runtime,
                observedVersion: BessieCompatibility.herdrVersion, observedProtocol: BessieCompatibility.protocolVersion,
                apiSocketPath: socket, apiHealthy: true)
        case .retrying(let runtime, _, _, _):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .apiConnection, finding: .previouslyHealthyLoss, runtime: runtime)
        case .lost(let runtime, _):
            runtimeDiagnostic = RuntimeDiagnosticSnapshot(stage: .apiConnection, finding: .previouslyHealthyLoss, runtime: runtime)
        }
        BessieDiagnosticLog.append(
            "Runtime stage=\(runtimeDiagnostic.stage.rawValue) source=\(runtimeDiagnostic.runtime?.source.rawValue ?? "unresolved") path=\(runtimeDiagnostic.runtime?.url.path ?? "unresolved") finding=\(runtimeDiagnostic.finding?.rawValue ?? "none") api=\(runtimeDiagnostic.apiHealthy)"
        )
    }

    private func diagnosticRuntime(for failure: RuntimeResolutionFailure) -> HerdrRuntime? {
        switch failure {
        case .bundledMissing, .bundledNotExecutable:
            bundledRuntimeURL.map { HerdrRuntime(url: $0, source: .bundled) }
        case .systemMissing:
            nil
        case .customMissing(let path), .customNotExecutable(let path):
            HerdrRuntime(
                url: URL(fileURLWithPath: path),
                source: runtimeSelection == .custom(URL(fileURLWithPath: path)) ? .custom : .explicitOverride
            )
        }
    }

    func launch(
        placement: NewProcessPlacement,
        process: NewProcessChoice,
        completion: (@MainActor (ProcessLaunchResult) -> Void)? = nil
    ) {
        guard let socketPath = terminalEndpoint?.socketPath else { return }
        actionInFlight = true
        actionError = nil
        Task.detached {
            do {
                let result = try HerdrProcessLauncher(api: HerdrSocketAPI(socketPath: socketPath)).launch(placement: placement, process: process)
                await MainActor.run {
                    self.projection = result.projection
                    self.actionInFlight = false
                    if let error = result.agentError {
                        self.actionError = "The pane is open, but the agent didn't start. \(error)"
                    }
                    completion?(result)
                }
            } catch {
                await MainActor.run { self.actionInFlight = false; self.actionError = error.localizedDescription }
            }
        }
    }

    private func ensureAgentCatalog(socketPath: String) {
        if catalogSocketPath != socketPath {
            catalogSocketPath = socketPath
            agentCatalog = AgentCatalog(items: [])
            catalogLoaded = false
            catalogLoadInFlight = false
        }
        guard !catalogLoaded, !catalogLoadInFlight else { return }
        catalogLoadInFlight = true
        Task.detached {
            do {
                let catalog = try AgentCatalog.load(api: HerdrSocketAPI(socketPath: socketPath))
                await MainActor.run {
                    guard self.catalogSocketPath == socketPath else { return }
                    self.agentCatalog = catalog
                    self.catalogLoaded = true
                    self.catalogLoadInFlight = false
                }
            } catch {
                await MainActor.run {
                    guard self.catalogSocketPath == socketPath else { return }
                    self.catalogLoaded = true
                    self.catalogLoadInFlight = false
                    self.actionError = "Couldn't load available agents. \(error.localizedDescription)"
                }
            }
        }
    }

    private static var repositoryRoot: URL {
        if let override = ProcessInfo.processInfo.environment["BESSIE_REPOSITORY_ROOT"] {
            return URL(fileURLWithPath: override)
        }
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func runtimeValidation(for bundledURL: URL) -> (validator: HerdrRuntimeValidator, lock: BundledRuntimeLock?) {
        let lock: BundledRuntimeLock?
        if let lockURL = Bundle.main.url(forResource: "runtime-lock", withExtension: "json", subdirectory: "Herdr"),
           let data = try? Data(contentsOf: lockURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sha256 = object["sha256"] as? String,
           let versionOutput = object["expected_version_output"] as? String,
           let protocolVersion = object["protocol"] as? Int {
            lock = BundledRuntimeLock(
                canonicalURL: bundledURL,
                sha256: sha256,
                versionOutput: versionOutput,
                protocolVersion: protocolVersion
            )
        } else {
            lock = nil
        }
        return (
            HerdrRuntimeValidator(
                inspect: { url in try inspectRuntime(at: url) },
                identity: { url in try runtimeIdentity(at: url) }
            ),
            lock
        )
    }

    nonisolated private static func inspectRuntime(at url: URL) throws -> RuntimeFileFacts {
        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists else {
            return RuntimeFileFacts(exists: false, regularFile: false, executable: false, arm64: false, sha256: nil, signatureValid: false)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        let architecture = try runTool("/usr/bin/file", arguments: [url.path])
        let checksum = try runTool("/usr/bin/shasum", arguments: ["-a", "256", url.path])
            .split(separator: " ").first.map(String.init)
        let signatureValid = (try? runTool("/usr/bin/codesign", arguments: ["--verify", "--strict", url.path])) != nil
        return RuntimeFileFacts(
            exists: true,
            regularFile: values.isRegularFile == true,
            executable: FileManager.default.isExecutableFile(atPath: url.path),
            arm64: architecture.contains("arm64"),
            sha256: checksum,
            signatureValid: signatureValid
        )
    }

    nonisolated private static func runtimeIdentity(at url: URL) throws -> HerdrServerIdentity {
        let output = try runTool(url.path, arguments: ["status", "client", "--json"])
        guard let data = output.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String,
              let protocolVersion = object["protocol"] as? Int
        else { throw HerdrClientError.process(path: url.path, message: "invalid client identity JSON") }
        return HerdrServerIdentity(version: version, protocolVersion: protocolVersion)
    }

    nonisolated private static func runTool(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw HerdrClientError.process(path: path, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

/// Keeps every configured Herdr connection live. The product shell uses one
/// session for workspace and terminal navigation at a time, while The herd is
/// the union of every connected session.
struct FleetConnectionIssue: Identifiable, Equatable {
    let id: String
    let label: String
    let title: String
    let detail: String
}

struct FleetNotificationSource {
    let connection: BessieConnectionDefinition
    let panes: [BessieNotificationPane]
}

enum FleetNotificationConnectionState: String {
    case ready, waiting, unavailable
}

@MainActor
final class ConnectionFleetViewModel: ObservableObject {
    @Published private(set) var activeModel: ConnectionViewModel?
    @Published private(set) var agents: [ConnectedAgentProjection] = []
    @Published private(set) var connectedConnectionIDs: Set<String> = []
    @Published private(set) var herdScope: ConnectionScope = .all
    @Published private(set) var routeFailure: String?
    @Published private(set) var connectedCount = 0
    @Published private(set) var connectionIssues: [FleetConnectionIssue] = []
    @Published private(set) var connectionHealth: [ConnectionHealth] = []

    private var models: [String: ConnectionViewModel] = [:]
    private var supplementalTerminalRegistries: [String: TerminalControllerRegistry] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]
    private let intentServer = AppIntentServer()
    private let defaults: UserDefaults
    private let performanceRecorder: BessiePerformanceRecorder
    private let scopeDefaultsKey = "Bessie.connectionScope"
    private var configuredConnections: [BessieConnectionDefinition] = []
    private var runtimeSelection: HerdrRuntimeSelection = .bundled
    private var bundledRuntimeURL: URL?
    private var preferredSelectedConnectionID: String = BessieConnectionDefinition.localBessie.id
    private var hasStarted = false
    private var refreshTask: Task<Void, Never>?
    private(set) var refreshPassCount = 0
    /// Connection IDs the fleet has been asked to start this process (launch set + on-demand).
    private(set) var startedConnectionIDs: Set<String> = []

    init(
        defaults: UserDefaults = .standard,
        performanceRecorder: BessiePerformanceRecorder = BessiePerformance.recorder
    ) {
        self.defaults = defaults
        self.performanceRecorder = performanceRecorder
        if let connectionID = defaults.string(forKey: scopeDefaultsKey), !connectionID.isEmpty {
            herdScope = .connection(id: connectionID)
        }
    }

    var activeConnectionID: String? { activeModel?.activeConnection.id }
    var presentation: ConnectPresentation { activeModel?.presentation ?? .initial }
    var connectionDefinitions: [BessieConnectionDefinition] { configuredConnections }
    var topologyConnections: [ConnectionTopologyProjection] {
        configuredConnections.compactMap { connection in
            guard let projection = models[connection.id]?.projection else { return nil }
            return ConnectionTopologyProjection(connection: connection, projection: projection)
        }
    }
    var scopeLabel: String {
        switch herdScope {
        case .all: return "All"
        case .connection(let id):
            guard let connection = configuredConnections.first(where: { $0.id == id }) else { return "All" }
            return connection.kind == .local ? "Local" : ConnectionDisplayLabel(connection: connection).short
        }
    }
    var notificationSources: [FleetNotificationSource] {
        models.values.compactMap { model in
            guard let projection = model.projection else { return nil }
            return FleetNotificationSource(
                connection: model.activeConnection,
                panes: BessieSurfaceProjection(projection: projection).notificationPanes
            )
        }.sorted { $0.connection.id < $1.connection.id }
    }

    func startIntentServer() {
        do { try intentServer.start() }
        catch { BessieDiagnosticLog.append("Intent socket unavailable: \(error.localizedDescription)") }
    }

    func stopIntentServer() { intentServer.stop() }

    func start(
        connections: [BessieConnectionDefinition],
        selectedConnectionID: String,
        runtimeSelection: HerdrRuntimeSelection,
        bundledRuntimeURL: URL?
    ) {
        preferredSelectedConnectionID = selectedConnectionID
        applyConfiguration(
            connections: connections,
            runtimeSelection: runtimeSelection,
            bundledRuntimeURL: bundledRuntimeURL
        )
        let startup = BessieLaunchConnections.startupConnections(
            connections: connections,
            selectedConnectionID: selectedConnectionID
        )
        for connection in startup {
            ensureStarted(connection)
        }
        let preferredID = BessieLaunchConnections.preferredActiveConnectionID(
            startupConnections: startup,
            selectedConnectionID: selectedConnectionID
        )
        if let preferredID {
            _ = setActiveConnection(id: preferredID)
        }
        if case .connection(let id) = herdScope, startedConnectionIDs.contains(id) {
            _ = setActiveConnection(id: id)
        }
        refresh()
        BessieDiagnosticLog.append(
            "Fleet launch start ids=\(startup.map(\.id).sorted().joined(separator: ",")) active=\(activeConnectionID ?? "-")"
        )
    }

    func sync(connections: [BessieConnectionDefinition], runtimeSelection: HerdrRuntimeSelection, bundledRuntimeURL: URL?) {
        applyConfiguration(
            connections: connections,
            runtimeSelection: runtimeSelection,
            bundledRuntimeURL: bundledRuntimeURL
        )
        // Newly enabled launch herds start immediately; turning launch off does not disconnect.
        for connection in connections where connection.connectAtLaunch {
            ensureStarted(connection)
        }
        if activeModel == nil {
            let startup = BessieLaunchConnections.startupConnections(
                connections: connections,
                selectedConnectionID: preferredSelectedConnectionID
            )
            if let preferredID = BessieLaunchConnections.preferredActiveConnectionID(
                startupConnections: startup,
                selectedConnectionID: preferredSelectedConnectionID
            ) {
                _ = setActiveConnection(id: preferredID)
            }
        }
        if case .connection(let id) = herdScope, startedConnectionIDs.contains(id) {
            _ = setActiveConnection(id: id)
        }
        refresh()
    }

    private func applyConfiguration(
        connections: [BessieConnectionDefinition],
        runtimeSelection: HerdrRuntimeSelection,
        bundledRuntimeURL: URL?
    ) {
        let desired = Set(connections.map(\.id))
        configuredConnections = connections
        self.runtimeSelection = runtimeSelection
        self.bundledRuntimeURL = bundledRuntimeURL
        hasStarted = true
        for id in models.keys where !desired.contains(id) {
            models[id]?.stop()
            models[id] = nil
            subscriptions[id] = nil
            startedConnectionIDs.remove(id)
        }
        if let activeConnectionID, !desired.contains(activeConnectionID) {
            activeModel = nil
        }
        if case .connection(let id) = herdScope, !desired.contains(id) {
            herdScope = .all
            defaults.removeObject(forKey: scopeDefaultsKey)
        }
    }

    @discardableResult
    private func ensureStarted(_ connection: BessieConnectionDefinition) -> ConnectionViewModel {
        if let existing = models[connection.id] {
            startedConnectionIDs.insert(connection.id)
            return existing
        }
        let model = ConnectionViewModel(
            runtimeSelection: runtimeSelection,
            bundledRuntimeURL: bundledRuntimeURL,
            intentDispatcher: intentServer.dispatcher,
            performanceRecorder: performanceRecorder
        )
        models[connection.id] = model
        subscriptions[connection.id] = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        }
        startedConnectionIDs.insert(connection.id)
        model.start(connection: connection)
        return model
    }

    @discardableResult
    private func setActiveConnection(id: String) -> ConnectionViewModel? {
        guard let model = models[id] else { return nil }
        activeModel = model
        preferredSelectedConnectionID = id
        return model
    }

    func setScope(_ scope: ConnectionScope) {
        switch scope {
        case .all:
            guard herdScope != .all else { return }
            herdScope = .all
            defaults.removeObject(forKey: scopeDefaultsKey)
        case .connection(let id):
            guard configuredConnections.contains(where: { $0.id == id }) else {
                herdScope = .all
                defaults.removeObject(forKey: scopeDefaultsKey)
                return
            }
            guard herdScope != scope else { return }
            herdScope = .connection(id: id)
            defaults.set(id, forKey: scopeDefaultsKey)
            _ = activate(connectionID: id)
        }
    }

    func statusLabel(connectionID: String) -> String {
        guard let health = connectionHealth.first(where: { $0.connectionID == connectionID }) else {
            return "Unavailable"
        }
        return health.isUsable ? "Connected" : health.phase
    }

    func activate(_ agent: ConnectedAgentProjection) -> ConnectionViewModel? {
        activate(connectionID: agent.connectionID)
    }

    func activate(connectionID: String) -> ConnectionViewModel? {
        guard let connection = configuredConnections.first(where: { $0.id == connectionID }) else { return nil }
        preferredSelectedConnectionID = connectionID
        let model = ensureStarted(connection)
        guard activeModel !== model else { return model }
        activeModel = model
        objectWillChange.send()
        return model
    }

    func model(connectionID: String) -> ConnectionViewModel? {
        models[connectionID]
    }

    func terminalRegistry(connectionID: String, activeRegistry: TerminalControllerRegistry) -> TerminalControllerRegistry? {
        guard let model = models[connectionID], let endpoint = model.terminalEndpoint,
              let projection = model.projection, connectedConnectionIDs.contains(connectionID)
        else { return nil }
        let registry: TerminalControllerRegistry
        if activeConnectionID == connectionID {
            registry = activeRegistry
        } else if let existing = supplementalTerminalRegistries[connectionID] {
            registry = existing
        } else {
            let created = TerminalControllerRegistry()
            created.setInitialTheme(activeRegistry.effectiveTheme)
            supplementalTerminalRegistries[connectionID] = created
            registry = created
        }
        registry.reconcile(
            presentedPaneIDs: projection.layouts.values.flatMap { $0.root.paneIDs },
            availablePaneIDs: Set(projection.panes.map(\.id)),
            endpoint: endpoint
        )
        return registry
    }

    func notificationConnectionState(connectionID: String) -> FleetNotificationConnectionState {
        guard let model = models[connectionID] else {
            // Configured but intentionally not started yet — not a transient wait.
            if hasStarted, configuredConnections.contains(where: { $0.id == connectionID }) {
                return .unavailable
            }
            return !hasStarted ? .waiting : .unavailable
        }
        if model.projection != nil, model.terminalEndpoint != nil { return .ready }
        switch model.presentation.status {
        case .notFound, .stopped, .incompatible, .lost:
            return .unavailable
        default:
            return .waiting
        }
    }

    func activateFirstReadyConnection() {
        guard let model = models.values.first(where: { $0.projection != nil && $0.terminalEndpoint != nil }) else { return }
        _ = activate(connectionID: model.activeConnection.id)
    }

    func reportRouteFailure(_ message: String) {
        routeFailure = message
    }

    func clearRouteFailure() {
        routeFailure = nil
    }

    func retryAll() {
        for model in models.values { model.retry() }
    }

    func retry(connectionID: String) {
        if let model = models[connectionID] {
            model.retry()
            return
        }
        guard let connection = configuredConnections.first(where: { $0.id == connectionID }) else { return }
        ensureStarted(connection)
    }

    func stop() {
        for model in models.values { model.stop() }
        models.removeAll()
        subscriptions.removeAll()
        supplementalTerminalRegistries.values.forEach { $0.releaseAll() }
        supplementalTerminalRegistries.removeAll()
        startedConnectionIDs.removeAll()
        refreshTask?.cancel()
        refreshTask = nil
        agents = []
        connectedConnectionIDs = []
        connectedCount = 0
        connectionIssues = []
        connectionHealth = []
        configuredConnections = []
        activeModel = nil
    }

    @discardableResult
    func scheduleRefresh() -> Task<Void, Never> {
        if let refreshTask { return refreshTask }
        let task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            refreshTask = nil
            refresh()
        }
        refreshTask = task
        return task
    }

    private func refresh() {
        refreshPassCount += 1
        let connected = models.values.filter { $0.projection != nil && $0.terminalEndpoint != nil }
        connectedCount = connected.count
        connectedConnectionIDs = Set(connected.map { $0.activeConnection.id })
        let registriesToRelease = supplementalTerminalRegistries.keys.filter {
            !connectedConnectionIDs.contains($0) || $0 == activeConnectionID
        }
        for connectionID in registriesToRelease {
            supplementalTerminalRegistries.removeValue(forKey: connectionID)?.releaseAll()
        }
        if case .connection(let id) = herdScope,
           let scoped = models[id], scoped.projection != nil, scoped.terminalEndpoint != nil {
            activeModel = scoped
        } else if activeModel == nil, let replacement = connected.first {
            activeModel = replacement
        }
        agents = connected.flatMap { model -> [ConnectedAgentProjection] in
            guard let projection = model.projection else { return [] }
            return projection.agents.map { agent in
                ConnectedAgentProjection(
                    connection: model.activeConnection,
                    agent: agent,
                    workspaceLabel: projection.workspaces.first { $0.id == agent.workspaceID }?.label,
                    tabLabel: projection.tabs.first { $0.id == agent.tabID }?.label
                )
            }
        }
        connectionHealth = configuredConnections.map { connection in
            if let model = models[connection.id] {
                return ConnectionHealth(connection: connection, presentation: model.presentation)
            }
            return ConnectionHealth(
                connection: connection,
                presentation: ConnectPresentation(
                    title: "Not started",
                    detail: connection.connectAtLaunch
                        ? "Will start at launch."
                        : "Starts when selected, or enable Start at launch.",
                    status: .stopped
                )
            )
        }.sorted { lhs, rhs in
            let lhsLabel = ConnectionDisplayLabel(
                connection: configuredConnections.first(where: { $0.id == lhs.connectionID }) ?? .localBessie
            ).short
            let rhsLabel = ConnectionDisplayLabel(
                connection: configuredConnections.first(where: { $0.id == rhs.connectionID }) ?? .localBessie
            ).short
            let comparison = lhsLabel.localizedCaseInsensitiveCompare(rhsLabel)
            return comparison == .orderedSame ? lhs.connectionID < rhs.connectionID : comparison == .orderedAscending
        }
        connectionIssues = models.values.compactMap { model in
            guard model.presentation.status != .connected else { return nil }
            return FleetConnectionIssue(
                id: model.activeConnection.id,
                label: ConnectionDisplayLabel(connection: model.activeConnection).short,
                title: model.presentation.title,
                detail: model.presentation.detail
            )
        }.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        let sources = connected.map { "\($0.activeConnection.name):\($0.projection?.agents.count ?? 0)" }.sorted().joined(separator: ",")
        BessieDiagnosticLog.append("Fleet connected=\(connectedCount) agents=\(agents.count) sources=\(sources)")
    }
}

struct ConnectView: View {
    @ObservedObject var fleet: ConnectionFleetViewModel
    let featureFlags: BessieFeatureFlags
    @ObservedObject var terminalRegistry: TerminalControllerRegistry
    @StateObject private var projects = ProjectsViewModel()
    @StateObject private var onboardingCoordinator = OnboardingCompletionCoordinator()
    @EnvironmentObject private var settings: BessieSettingsModel
    @Environment(\.bessieDensity) private var density
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @State private var setupAutomationStarted = false
    @State private var navigationRequest: ProductNavigationRequest?
    @State private var zenState = BessieZenPresentationState.inactive
    @State private var onboardingPath = Self.designOnboardingPath
    @State private var showingColdOpen: Bool
    @State private var splashEntryGeneration = -1

    init(
        fleet: ConnectionFleetViewModel,
        featureFlags: BessieFeatureFlags,
        terminalRegistry: TerminalControllerRegistry,
        initiallyShowsColdOpen: Bool
    ) {
        self.fleet = fleet
        self.featureFlags = featureFlags
        self.terminalRegistry = terminalRegistry
        _showingColdOpen = State(initialValue: initiallyShowsColdOpen)
    }

    private var presentation: ConnectPresentation { fleet.presentation }
    private var coldOpenBootstrapSettled: Bool {
        switch presentation.status {
        case .connected, .notFound, .stopped, .incompatible, .lost: true
        case .notChecked, .connecting, .retrying: false
        }
    }
    /// Video only on first-run / Run Setup Again (and the splash design artboard).
    /// Ordinary completed launches keep the native "joining the herd" loader.
    private var playsColdOpenVideo: Bool {
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "09" {
            return true
        }
        return !settings.onboarding.completed
    }
    private var notificationActivationSignature: String {
        let pending = notifications.pendingRoute
        let routeState = pending.map {
            fleet.notificationConnectionState(connectionID: $0.target.connectionID).rawValue
        } ?? "-"
        return "\(pending?.id.uuidString ?? "-")|\(pending?.target.connectionID ?? "-")|\(routeState)|\(fleet.activeConnectionID ?? "-")|\(settings.connections.map(\.id).joined(separator: ","))"
    }
    // Non-active + windowless active reconcile lives on BessieAppDelegate so it
    // survives main-window close (menu-bar companion). Do not duplicate it here.

    var body: some View {
        Group {
            if showingColdOpen {
                ColdOpenSplashView(
                    bootstrapSettled: coldOpenBootstrapSettled,
                    playsVideo: playsColdOpenVideo
                ) {
                    showingColdOpen = false
                }
            } else if let model = fleet.activeModel,
               let projection = model.projection,
               let endpoint = model.terminalEndpoint {
                ZStack {
                    BessieProductShell(
                        model: model,
                        fleet: fleet,
                        projection: projection,
                        terminalEndpoint: endpoint,
                        terminalRegistry: terminalRegistry,
                        navigationRequest: $navigationRequest,
                        zenState: $zenState,
                        projects: projects,
                        featureFlags: featureFlags
                    )
                    .onAppear {
                        model.markShellReady()
                    }
                    if !settings.onboarding.completed {
                        OnboardingView(
                            projects: projects,
                            state: settings.onboarding,
                            connected: true,
                            completionAvailable: onboardingCoordinator.canSubmit,
                            connectionError: nil,
                            path: $onboardingPath,
                            continueSetup: {
                                settings.advanceSetup(runtimeReady: true, sessionReady: true,
                                    workspaceReady: !projection.workspaces.isEmpty,
                                    terminalControllerReady: terminalRegistry.controllers.values.contains(where: { $0.hasReadyFrame }))
                            },
                            finishSetup: {
                                onboardingCoordinator.submit(
                                    connectionID: settings.selectedConnectionID,
                                    path: onboardingPath
                                )
                            },
                            cancelSetup: {
                                guard !onboardingCoordinator.materializationStarted else { return }
                                try? onboardingCoordinator.cancelBeforeMaterialization()
                                settings.cancelSetupAgainBeforeMaterialization()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(BessieOnboardingSurface(base: BessieDesign.background))
                    } else if model.runtimeDiagnostic.finding == .terminalControlUnavailable {
                        TroubleView(diagnostic: model.runtimeDiagnostic) { model.retry() }
                            .frame(maxWidth: 760, maxHeight: 560)
                    }
                }
                .task(id: projection.workspaces.count) {
                    runSetupAutomation(model: model, projection: projection)
                }
                .task(id: terminalRegistry.controllers.values.contains(where: { $0.hasReadyFrame })) {
                    runSetupAutomation(model: model, projection: projection)
                    resumeOnboardingCompletion(model: model, projection: projection)
                }
            } else {
                if !settings.onboarding.completed {
                    OnboardingView(
                        projects: projects,
                        state: settings.onboarding,
                        connected: false,
                        completionAvailable: false,
                        connectionError: "\(presentation.title). \(presentation.detail)",
                        path: $onboardingPath,
                        continueSetup: {},
                        finishSetup: {},
                        cancelSetup: {
                            guard !onboardingCoordinator.materializationStarted else { return }
                            try? onboardingCoordinator.cancelBeforeMaterialization()
                            settings.cancelSetupAgainBeforeMaterialization()
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BessieOnboardingSurface(base: BessieDesign.background))
                } else if zenState.isActive {
                    BessieZenDisconnectedSurface(
                        connection: fleet.activeModel?.activeConnection ?? .localBessie,
                        presentation: presentation,
                        retry: retryActiveConnection,
                        exit: { zenState.exit() }
                    )
                } else if let diagnostic = fleet.activeModel?.runtimeDiagnostic, diagnostic.finding != nil {
                    TroubleView(diagnostic: diagnostic) { retryActiveConnection() }
                } else {
                    connectPanel
                }
            }
        }
        .environmentObject(fleet)
        .task {
            onboardingCoordinator.configure(service: ProductionOnboardingMaterializationService(
                fleet: fleet,
                remoteBootstrap: .production { connection in
                    try DispatchQueue.main.sync { try settings.registerOnboardingConnection(connection) }
                },
                register: settings.registerOnboardingConnection
            ))
            enterOnboardingIfNeeded()
            fleet.start(
                connections: settings.connections,
                selectedConnectionID: settings.selectedConnectionID,
                runtimeSelection: settings.runtimeSelection,
                bundledRuntimeURL: Self.bundledRuntimeURL
            )
        }
        .onChange(of: settings.setupEntryGeneration) { _, _ in enterOnboardingIfNeeded() }
        .onChange(of: onboardingCoordinator.stage) { _, stage in
            guard stage == .waitingForFirstFrame,
                  let attempt = onboardingCoordinator.attempt,
                  let model = fleet.activate(connectionID: attempt.connectionID),
                  let projection = model.projection,
                  let target = BessieSurfaceProjection(projection: projection).openTarget(paneID: attempt.paneID ?? "")
            else { return }
            navigationRequest = ProductNavigationRequest(connectionID: attempt.connectionID, workspaceID: target.workspaceID, tabID: target.tabID, paneID: target.paneID)
            terminalRegistry.focusWhenPresented(paneID: target.paneID)
            settings.advanceSetup(runtimeReady: true, sessionReady: true, workspaceReady: true, terminalControllerReady: false)
            resumeOnboardingCompletion(model: model, projection: projection)
        }
        .onChange(of: settings.connections) { _, connections in
            fleet.sync(connections: connections, runtimeSelection: settings.runtimeSelection, bundledRuntimeURL: Self.bundledRuntimeURL)
        }
        .onChange(of: settings.runtimeSelection) { _, selection in
            terminalRegistry.releaseAll(); fleet.stop()
            fleet.start(
                connections: settings.connections,
                selectedConnectionID: settings.selectedConnectionID,
                runtimeSelection: selection,
                bundledRuntimeURL: Self.bundledRuntimeURL
            )
        }
        .onChange(of: settings.selectedConnectionID) { _, id in
            _ = fleet.activate(connectionID: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .bessieCommand)) { notification in
            if notification.object as? BessieShortcutCommand == .exitZen,
               fleet.activeModel?.projection == nil {
                zenState.exit()
            }
        }
        .onChange(of: fleet.activeConnectionID) { _, id in
            terminalRegistry.releaseAll(unlessConnectedTo: id)
            if let id, settings.selectedConnectionID != id {
                settings.selectConnection(id)
            }
        }
        .task(id: notificationActivationSignature) {
            guard let route = notifications.pendingRoute else { return }
            switch fleet.notificationConnectionState(connectionID: route.target.connectionID) {
            case .ready, .waiting:
                _ = fleet.activate(connectionID: route.target.connectionID)
            case .unavailable:
                fleet.activateFirstReadyConnection()
                notifications.consumePendingRoute(route)
                fleet.reportRouteFailure(
                    "Couldn't open the notification target because its Herdr connection is unavailable. Reconnect it, then find the agent in The herd."
                )
            }
        }
        .onChange(of: terminalRegistry.diagnosticRevision) { _, _ in
            guard let model = fleet.activeModel else { return }
            let facts = terminalRegistry.diagnosticFacts
            model.updateTerminalDiagnostic(facts)
            if !settings.onboarding.completed, facts.healthy {
                settings.terminalBecameReady()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            shutdownForAppExit()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bessieMainWindowWillClose)) { _ in
            terminalRegistry.releaseAll()
        }
        .alert("Couldn't open pane", isPresented: Binding(
            get: { fleet.routeFailure != nil },
            set: { if !$0 { fleet.clearRouteFailure() } }
        )) {
            Button("OK") { fleet.clearRouteFailure() }
        } message: {
            Text(fleet.routeFailure ?? "The notification target is unavailable.")
        }
        .background(BessieWindowSnapshotProbe())
    }

    private func shutdownForAppExit() {
        projects.updateConnection(nil, snapshot: nil)
        terminalRegistry.releaseAll()
        fleet.stop()
    }

    private func enterOnboardingIfNeeded() {
        guard !settings.onboarding.completed,
              splashEntryGeneration != settings.setupEntryGeneration else { return }
        splashEntryGeneration = settings.setupEntryGeneration
        if let artboard = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"],
           (10...13).contains(Int(artboard) ?? 0) {
            showingColdOpen = false
            return
        }
        showingColdOpen = true
    }

    private static var designOnboardingPath: String {
        guard let artboard = ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"],
              (10...13).contains(Int(artboard) ?? 0)
        else { return "" }
        return "/tmp/bessie-design-preview"
    }

    private var connectPanel: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        BessieBrandMark()
                            .padding(.bottom, 30)

                        Text("CONNECT")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.55)
                            .foregroundStyle(BessieDesign.faint)
                            .padding(.bottom, 8)

                        Text(presentation.title)
                            .font(.system(size: 28, weight: .medium))
                            .tracking(-0.56)
                            .foregroundStyle(BessieDesign.strong)

                        Text(presentation.detail)
                            .font(.system(size: 13))
                            .lineSpacing(5)
                            .foregroundStyle(BessieDesign.text)
                            .frame(maxWidth: 560, alignment: .leading)
                            .padding(.top, 9)
                            .padding(.bottom, 24)

                        VStack(spacing: 0) {
                            ConnectFactRow(
                                symbol: "terminal",
                                title: activeConnection.kind == .local ? "Herdr" : "Remote Herdr",
                                detail: activeConnection.kind == .local
                                    ? (presentation.status == .notFound ? "Not installed" : "Included runtime")
                                    : "\(activeConnection.sshHost ?? "Unknown host") · session \(activeConnection.session ?? "default")",
                                status: activeConnection.kind == .local
                                    ? (presentation.status == .notFound ? "NOT FOUND" : "FOUND")
                                    : (presentation.status == .connected ? "FOUND" : "CHECKING")
                            )
                            Divider().overlay(BessieDesign.border)
                            ConnectFactRow(
                                symbol: "point.3.connected.trianglepath.dotted",
                                title: activeConnection.kind == .local ? "Local session" : "SSH connection",
                                detail: statusText,
                                status: presentation.status == .connected ? "CONNECTED" : "WAITING"
                            )
                            Divider().overlay(BessieDesign.border)
                            ConnectFactRow(
                                symbol: "checkmark.shield",
                                title: "Compatibility",
                                detail: "Public protocol \(BessieCompatibility.protocolVersion)",
                                status: presentation.status == .incompatible ? "UNSUPPORTED" : "REQUIRED"
                            )
                        }
                        .background(BessieDesign.panel)
                        .overlay {
                            RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                                .stroke(BessieDesign.border, lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))

                        HStack(spacing: 8) {
                            if allowsRetry {
                                Button("Try again", systemImage: "arrow.clockwise") { retryActiveConnection() }
                                    .buttonStyle(BessiePrimaryButtonStyle())
                            }
                            if presentation.status != .connecting {
                                DisclosureGroup("How to connect") {
                                    Text(connectionHelp)
                                        .font(.system(size: 11))
                                        .foregroundStyle(BessieDesign.subtle)
                                        .padding(.top, 6)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(BessieDesign.text)
                            }
                        }
                        .padding(.top, 17)

                    }
                    .padding(40)
                    .frame(maxWidth: 760, alignment: .leading)
                    .bessieSurface(base: BessieDesign.background)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, density.cardGap)
                .padding(.bottom, max(2, density.cardGap - 2))
            }
        }
        .tint(BessieDesign.strong)
    }

    private static var bundledRuntimeURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Herdr/herdr")
    }

    private func runSetupAutomation(model: ConnectionViewModel, projection: HerdrSessionProjection) {
        guard ProcessInfo.processInfo.environment["BESSIE_SETUP_AUTOMATION"] == "1",
              !settings.onboarding.completed
        else { return }
        if projection.workspaces.isEmpty {
            guard !setupAutomationStarted else { return }
            setupAutomationStarted = true
            model.perform(.workspaceCreate(cwd: nil, label: "Bessie setup verification", focus: true)) { _ in
                setupAutomationStarted = false
            }
            return
        }
        while settings.onboarding.step != .notifications {
            settings.advanceSetup(runtimeReady: true, sessionReady: true, workspaceReady: true, terminalControllerReady: false)
        }
        guard terminalRegistry.controllers.values.contains(where: { $0.hasReadyFrame }),
              !setupAutomationStarted
        else { return }
        setupAutomationStarted = true
        completeSetup(model: model, projection: projection)
    }

    private func completeSetup(model: ConnectionViewModel, projection: HerdrSessionProjection) {
        let expectedPaneID = onboardingCoordinator.attempt?.paneID
        guard let readyPaneID = expectedPaneID ?? terminalRegistry.controllers.first(where: { $0.value.hasReadyFrame })?.key,
              terminalRegistry.controllers[readyPaneID]?.hasReadyFrame == true,
              let target = BessieSurfaceProjection(projection: projection).openTarget(paneID: readyPaneID)
        else {
            setupAutomationStarted = false
            return
        }
        model.openPane(target) { _ in
            setupAutomationStarted = false
            guard settings.finishSetup(
                connected: true,
                hasWorkspace: true,
                terminalControllerReady: true
            ) else { return }
            try? onboardingCoordinator.advance(.completed)
            navigationRequest = ProductNavigationRequest(
                connectionID: model.activeConnection.id,
                workspaceID: target.workspaceID,
                tabID: target.tabID,
                paneID: target.paneID
            )
        } failure: {
            setupAutomationStarted = false
            settings.reportOnboardingFocusFailure()
        }
    }

    private func resumeOnboardingCompletion(model: ConnectionViewModel, projection: HerdrSessionProjection) {
        guard onboardingCoordinator.stage == .waitingForFirstFrame,
              let paneID = onboardingCoordinator.attempt?.paneID,
              terminalRegistry.controllers[paneID]?.hasReadyFrame == true
        else { return }
        completeSetup(model: model, projection: projection)
    }

    private var allowsRetry: Bool {
        [.notFound, .stopped, .incompatible, .lost].contains(presentation.status)
    }

    private var activeConnection: BessieConnectionDefinition {
        fleet.activeModel?.activeConnection ?? .localBessie
    }

    private var connectionLabel: ConnectionDisplayLabel {
        ConnectionDisplayLabel(connection: activeConnection)
    }

    private var connectionHelp: String {
        if activeConnection.kind == .ssh {
            return "Start Herdr session \(activeConnection.session ?? "default") on \(activeConnection.sshHost ?? "the remote Mac"), then try again. Bessie uses your OpenSSH config and leaves remote Herdr running when it disconnects."
        }
        return "Bessie's included compatible Herdr runtime could not start. Reinstall this copy of Bessie or open Trouble for a safe diagnostic report."
    }

    private func retryActiveConnection() {
        guard let id = fleet.activeConnectionID else { return }
        fleet.retry(connectionID: id)
    }

    private var statusText: String {
        switch presentation.status {
        case .notChecked: "Checking for Herdr"
        case .notFound: "Herdr not found"
        case .stopped: "Server not running"
        case .incompatible: "Unsupported version"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .retrying: "Reconnecting"
        case .lost: "Disconnected"
        }
    }
}

private struct ConnectFactRow: View {
    let symbol: String
    let title: String
    let detail: String
    let status: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(BessieDesign.text)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(BessieDesign.strong)
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.subtle)
                    .lineLimit(1)
            }
            Spacer()
            Text(status)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(BessieDesign.text)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(BessieDesign.selected)
                .overlay {
                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                        .stroke(BessieDesign.border, lineWidth: 1)
                }
        }
        .padding(.horizontal, 13)
        .frame(height: 54)
    }
}
