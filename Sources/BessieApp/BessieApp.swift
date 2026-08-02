import BessieCore
import Combine
import Foundation
import GhosttyTerminal
import SwiftUI

@main
struct BessieApp: App {
    @StateObject private var settings = BessieSettingsModel()
    @StateObject private var notifications = BessieNotificationCoordinator()

    var body: some Scene {
        WindowGroup {
            ConnectView()
                .environmentObject(settings)
                .environmentObject(notifications)
                .onAppear { BessieAppIconController.apply(settings.preferences.appIcon) }
                .onChange(of: settings.preferences.appIcon) { _, icon in
                    BessieAppIconController.apply(icon)
                }
                .preferredColorScheme(.dark)
                .frame(minWidth: 1080, minHeight: 680)
                .background(BessieDesign.window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)

        Settings {
            BessieSettingsView()
                .environmentObject(settings)
                .environmentObject(notifications)
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
    @Published private(set) var activeConnection: BessieConnectionDefinition = .localBessie
    @Published private(set) var projectMaterializationConnection: BessieProjectMaterializationConnection?
    private var connectionTask: Task<Void, Never>?
    private var connectionRunner: HerdrConnectionRunner?
    private var remoteBridge: RemoteHerdrBridge?
    private var connectionToken = UUID()
    private var actionClient: HerdrActionClient?
    private var catalogSocketPath: String?
    private var catalogLoadInFlight = false
    private var projectHandoffToken: UUID?
    @Published private(set) var catalogLoaded = false
    private let runtimeSelection: HerdrRuntimeSelection
    private let bundledRuntimeURL: URL?
    private let runtimeValidator: HerdrRuntimeValidator?
    private let bundledRuntimeLock: BundledRuntimeLock?

    init(runtimeSelection: HerdrRuntimeSelection = .bundled, bundledRuntimeURL: URL? = nil) {
        self.runtimeSelection = runtimeSelection
        self.bundledRuntimeURL = bundledRuntimeURL
        let validation = bundledRuntimeURL.map(Self.runtimeValidation(for:))
        runtimeValidator = validation?.validator
        bundledRuntimeLock = validation?.lock
    }

    func start(connection: BessieConnectionDefinition = .localBessie) {
        guard connectionTask == nil else { return }
        activeConnection = connection
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
                    let socketPath = try await Task.detached { try bridge.start() }.value
                    guard !Task.isCancelled, self.connectionToken == token else { bridge.stop(); return }
                    self.remoteBridge = bridge
                    environment["BESSIE_HERDR_SOCKET_PATH"] = socketPath
                    environment["BESSIE_HERDR_AUTOSTART"] = "0"
                } catch {
                    guard self.connectionToken == token else { return }
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
                bundledRuntimeLock: bundledRuntimeLock
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
                    self?.actionClient = endpoint.map { HerdrActionClient(api: HerdrSocketAPI(socketPath: $0.socketPath)) }
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
        connectionRunner?.cancel()
        connectionTask?.cancel()
        connectionTask = nil
        connectionRunner = nil
        remoteBridge?.stop()
        remoteBridge = nil
        projectMaterializationConnection = nil
    }

    func perform(_ action: HerdrAction, completion: (@MainActor (HerdrSessionProjection) -> Void)? = nil) {
        guard let actionClient else { return }
        actionInFlight = true
        actionError = nil
        Task.detached {
            do {
                let projection = try actionClient.perform(action)
                await MainActor.run {
                    self.projection = projection
                    self.actionInFlight = false
                    completion?(projection)
                }
            } catch {
                await MainActor.run {
                    self.actionInFlight = false
                    self.actionError = error.localizedDescription
                }
            }
        }
    }

    func openPane(_ target: PaneOpenTarget, completion: (@MainActor (HerdrSessionProjection) -> Void)? = nil) {
        guard let actionClient else { return }
        actionInFlight = true
        actionError = nil
        Task.detached {
            do {
                let projection = try actionClient.perform([
                    .workspaceFocus(id: target.workspaceID),
                    .tabFocus(id: target.tabID),
                    .paneFocus(id: target.paneID),
                ])
                await MainActor.run {
                    self.projection = projection
                    self.actionInFlight = false
                    completion?(projection)
                }
            } catch {
                await MainActor.run {
                    self.actionInFlight = false
                    self.actionError = error.localizedDescription
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
              }),
              let actionClient
        else { return }
        var actions: [HerdrAction] = [.workspaceFocus(id: handoff.workspaceID)]
        if let tabID = handoff.tabID { actions.append(.tabFocus(id: tabID)) }
        if let paneID = handoff.paneID { actions.append(.paneFocus(id: paneID)) }
        actionInFlight = true
        actionError = nil
        let handoffToken = UUID()
        projectHandoffToken = handoffToken
        Task.detached {
            do {
                let projection = try actionClient.perform(actions)
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

@MainActor
final class ConnectionFleetViewModel: ObservableObject {
    @Published private(set) var activeModel: ConnectionViewModel?
    @Published private(set) var agents: [ConnectedAgentProjection] = []
    @Published private(set) var connectedCount = 0
    @Published private(set) var connectionIssues: [FleetConnectionIssue] = []

    private var models: [String: ConnectionViewModel] = [:]
    private var subscriptions: [String: AnyCancellable] = [:]

    var activeConnectionID: String? { activeModel?.activeConnection.id }
    var presentation: ConnectPresentation { activeModel?.presentation ?? .initial }

    func start(connections: [BessieConnectionDefinition], runtimeSelection: HerdrRuntimeSelection, bundledRuntimeURL: URL?) {
        sync(connections: connections, runtimeSelection: runtimeSelection, bundledRuntimeURL: bundledRuntimeURL)
    }

    func sync(connections: [BessieConnectionDefinition], runtimeSelection: HerdrRuntimeSelection, bundledRuntimeURL: URL?) {
        let desired = Set(connections.map(\.id))
        for id in models.keys where !desired.contains(id) {
            models[id]?.stop()
            models[id] = nil
            subscriptions[id] = nil
        }
        for connection in connections where models[connection.id] == nil {
            let model = ConnectionViewModel(runtimeSelection: runtimeSelection, bundledRuntimeURL: bundledRuntimeURL)
            models[connection.id] = model
            subscriptions[connection.id] = model.objectWillChange.sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.refresh()
                }
            }
            model.start(connection: connection)
        }
        if activeModel == nil {
            activeModel = connections.compactMap { models[$0.id] }.first
        }
        refresh()
    }

    func activate(_ agent: ConnectedAgentProjection) -> ConnectionViewModel? {
        activate(connectionID: agent.connectionID)
    }

    func activate(connectionID: String) -> ConnectionViewModel? {
        guard let model = models[connectionID] else { return nil }
        activeModel = model
        objectWillChange.send()
        return model
    }

    func retryAll() {
        for model in models.values { model.retry() }
    }

    func stop() {
        for model in models.values { model.stop() }
        models.removeAll()
        subscriptions.removeAll()
        agents = []
        connectedCount = 0
        connectionIssues = []
        activeModel = nil
    }

    private func refresh() {
        let connected = models.values.filter { $0.projection != nil && $0.terminalEndpoint != nil }
        connectedCount = connected.count
        if activeModel?.projection == nil, let replacement = connected.first {
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
    @StateObject private var fleet = ConnectionFleetViewModel()
    @StateObject private var terminalRegistry = TerminalControllerRegistry()
    @StateObject private var projects = ProjectsViewModel()
    @EnvironmentObject private var settings: BessieSettingsModel
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @State private var setupAutomationStarted = false

    private var presentation: ConnectPresentation { fleet.presentation }
    private var notificationActivationSignature: String {
        let pendingConnectionID = notifications.pendingTarget?.connectionID ?? "-"
        return "\(pendingConnectionID)|\(fleet.activeConnectionID ?? "-")|\(settings.connections.map(\.id).joined(separator: ","))"
    }

    var body: some View {
        Group {
            if let model = fleet.activeModel,
               let projection = model.projection,
               let endpoint = model.terminalEndpoint {
                ZStack {
                    BessieProductShell(
                        model: model,
                        fleet: fleet,
                        projection: projection,
                        terminalEndpoint: endpoint,
                        terminalRegistry: terminalRegistry,
                        projects: projects
                    )
                    if !settings.onboarding.completed {
                        OnboardingView(
                            state: settings.onboarding,
                            connected: true,
                            hasWorkspace: !projection.workspaces.isEmpty,
                            terminalControllerReady: terminalRegistry.controllers.values.contains(where: { $0.hasReadyFrame }),
                            createWorkspace: { model.perform(.workspaceCreate(cwd: nil, label: "My workspace", focus: true)) },
                            continueSetup: {
                                settings.advanceSetup(runtimeReady: true, sessionReady: true,
                                    workspaceReady: !projection.workspaces.isEmpty,
                                    terminalControllerReady: terminalRegistry.controllers.values.contains(where: { $0.hasReadyFrame }))
                            }
                        )
                        .frame(maxWidth: 680, maxHeight: 460)
                        .shadow(radius: 20)
                    } else if model.runtimeDiagnostic.finding == .terminalControlUnavailable {
                        TroubleView(diagnostic: model.runtimeDiagnostic) { model.retry() }
                            .frame(maxWidth: 760, maxHeight: 560)
                            .shadow(radius: 20)
                    }
                }
                .task(id: projection.workspaces.count) {
                    runSetupAutomation(model: model, projection: projection)
                }
            } else {
                if let diagnostic = fleet.activeModel?.runtimeDiagnostic, diagnostic.finding != nil {
                    TroubleView(diagnostic: diagnostic) { fleet.retryAll() }
                } else {
                    connectPanel
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { fleet.start(connections: settings.connections, runtimeSelection: settings.runtimeSelection, bundledRuntimeURL: Self.bundledRuntimeURL) }
        .onChange(of: settings.connections) { _, connections in
            fleet.sync(connections: connections, runtimeSelection: settings.runtimeSelection, bundledRuntimeURL: Self.bundledRuntimeURL)
        }
        .onChange(of: settings.runtimeSelection) { _, selection in
            terminalRegistry.releaseAll(); fleet.stop()
            fleet.start(connections: settings.connections, runtimeSelection: selection, bundledRuntimeURL: Self.bundledRuntimeURL)
        }
        .onChange(of: fleet.activeConnectionID) { _, _ in
            terminalRegistry.releaseAll()
        }
        .task(id: notificationActivationSignature) {
            guard let target = notifications.pendingTarget else { return }
            _ = fleet.activate(connectionID: target.connectionID)
        }
        .onChange(of: terminalRegistry.diagnosticRevision) { _, _ in
            guard let model = fleet.activeModel else { return }
            let facts = terminalRegistry.diagnosticFacts
            model.updateTerminalDiagnostic(facts)
            if !settings.onboarding.completed, facts.healthy {
                settings.terminalBecameReady()
            }
        }
        .onDisappear {
            projects.updateConnection(nil, snapshot: nil)
            terminalRegistry.releaseAll()
            fleet.stop()
        }
        .background(BessieWindowSnapshotProbe())
    }

    private var connectPanel: some View {
        ZStack {
            BessieCowprintTexture(base: BessieDesign.window, crop: .connect, intensityScale: 1.15)
                .ignoresSafeArea()

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
                                title: "Herdr",
                                detail: presentation.status == .notFound ? "Not installed" : "Version 0.7.5",
                                status: presentation.status == .notFound ? "NOT FOUND" : "FOUND"
                            )
                            Divider().overlay(BessieDesign.border)
                            ConnectFactRow(
                                symbol: "point.3.connected.trianglepath.dotted",
                                title: "Local session",
                                detail: statusText,
                                status: presentation.status == .connected ? "CONNECTED" : "WAITING"
                            )
                            Divider().overlay(BessieDesign.border)
                            ConnectFactRow(
                                symbol: "checkmark.shield",
                                title: "Required version",
                                detail: "Herdr 0.7.5 · protocol 17",
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
                                Button("Try again", systemImage: "arrow.clockwise") { fleet.retryAll() }
                                    .buttonStyle(BessiePrimaryButtonStyle())
                            }
                            if presentation.status != .connecting {
                                DisclosureGroup("How to connect") {
                                    Text("Install Herdr 0.7.5. Bessie starts its named local session automatically. If Herdr is installed somewhere unusual, set BESSIE_HERDR_PATH to the executable.")
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
                    .bessieSurface(base: BessieDesign.background, crop: .connect)
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, BessieDesign.cardGap)
                .padding(.bottom, BessieDesign.cardGap - 2)

                HStack(spacing: 16) {
                    Text("BESSIE 0.1.0").foregroundStyle(BessieDesign.strong)
                    Text("LOCAL HERDR")
                    Spacer()
                    Text(statusText.uppercased())
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(BessieDesign.subtle)
                .padding(.horizontal, 13)
                .frame(height: 26)
                .overlay(alignment: .top) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
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
        while settings.onboarding.step != .terminal {
            settings.advanceSetup(runtimeReady: true, sessionReady: true, workspaceReady: true, terminalControllerReady: false)
        }
    }

    private var allowsRetry: Bool {
        [.notFound, .stopped, .incompatible, .lost].contains(presentation.status)
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
