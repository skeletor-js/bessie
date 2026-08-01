import BessieCore
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
    @Published private(set) var actionInFlight = false
    private var connectionTask: Task<Void, Never>?
    private var connectionRunner: HerdrConnectionRunner?
    private var actionClient: HerdrActionClient?
    private var catalogSocketPath: String?
    private var catalogLoadInFlight = false
    @Published private(set) var catalogLoaded = false

    func start() {
        guard connectionTask == nil else { return }
        if let runToken = ProcessInfo.processInfo.environment["BESSIE_RUN_TOKEN"] {
            let processID = ProcessInfo.processInfo.processIdentifier
            BessieDiagnosticLog.append("App run=\(runToken) pid=\(processID)")
        }
        let runner = HerdrConnectionRunner(repositoryRoot: Self.repositoryRoot)
        connectionRunner = runner
        connectionTask = Task {
            await runner.run { [weak self] state in
                BessieDiagnosticLog.append(state.label)
                let projection: HerdrSessionProjection?
                let endpoint: HerdrTerminalEndpoint?
                if case .connected(let runtime, let socketPath, let snapshot) = state {
                    projection = try? HerdrSessionProjection(snapshot: snapshot)
                    endpoint = HerdrTerminalEndpoint(executablePath: runtime.url.path, socketPath: socketPath)
                    if let projection {
                        let labels = projection.workspaces.map(\.label).joined(separator: ",")
                        BessieDiagnosticLog.append("Snapshot workspace_labels=\(labels)")
                    }
                } else {
                    projection = nil
                    endpoint = nil
                }
                Task { @MainActor in
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
        connectionRunner?.cancel()
        connectionTask?.cancel()
        connectionTask = nil
        connectionRunner = nil
        catalogLoaded = false
        start()
    }

    func stop() {
        connectionRunner?.cancel()
        connectionTask?.cancel()
        connectionTask = nil
        connectionRunner = nil
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

    func clearActionError() { actionError = nil }

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

}

struct ConnectView: View {
    @StateObject private var model = ConnectionViewModel()
    @StateObject private var terminalRegistry = TerminalControllerRegistry()
    @EnvironmentObject private var settings: BessieSettingsModel

    private var presentation: ConnectPresentation { model.presentation }

    var body: some View {
        Group {
            if presentation.status == .connected, let projection = model.projection, let endpoint = model.terminalEndpoint {
                BessieProductShell(model: model, projection: projection, terminalEndpoint: endpoint, terminalRegistry: terminalRegistry)
            } else {
                connectPanel
            }
        }
        .preferredColorScheme(.dark)
        .task { model.start() }
        .onChange(of: presentation.status) { _, status in
            if status != .connected { terminalRegistry.releaseAll() }
        }
        .onDisappear { terminalRegistry.releaseAll(); model.stop() }
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
                                Button("Try again", systemImage: "arrow.clockwise") { model.retry() }
                                    .buttonStyle(BessiePrimaryButtonStyle())
                            }
                            if presentation.status != .connecting {
                                DisclosureGroup("How to connect") {
                                    Text("Install Herdr 0.7.5 and start its local server. If Herdr isn't on your PATH, set BESSIE_HERDR_PATH to the executable.")
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
