import AppKit
import BessieCore
import CoreGraphics
import Darwin
import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class BessieSettingsModel: ObservableObject {
    @Published var preferences: BessiePreferences { didSet { persist() } }
    @Published private(set) var lastWorkspaceIDByConnectionID: [String: String]
    private let legacyLastWorkspaceID: String?
    @Published private(set) var connections: [BessieConnectionDefinition]
    @Published private(set) var selectedConnectionID: String
    @Published private(set) var connectionError: String?
    @Published private(set) var runtimeSelection: HerdrRuntimeSelection
    @Published private(set) var onboarding = OnboardingState()
    @Published private(set) var runtimePersistenceError: String?
    private let store: BessiePresentationStore
    private let connectionStore: BessieConnectionStore
    private let runtimeStore: HerdrRuntimeSelectionStore

    init() {
        let environment = ProcessInfo.processInfo.environment
        let url: URL
        if let path = environment["BESSIE_PRESENTATION_PATH"] {
            url = URL(fileURLWithPath: path)
        } else {
            url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Bessie", isDirectory: true)
                .appendingPathComponent("presentation.json")
        }
        store = BessiePresentationStore(url: url)
        let state = try? store.load()
        preferences = state?.preferences ?? BessiePreferences()
        legacyLastWorkspaceID = state?.lastWorkspaceID
        lastWorkspaceIDByConnectionID = state?.lastWorkspaceIDByConnectionID ?? [:]
        let connectionURL = environment["BESSIE_CONNECTIONS_PATH"].map(URL.init(fileURLWithPath:))
            ?? url.deletingLastPathComponent().appendingPathComponent("connections.json")
        connectionStore = BessieConnectionStore(url: connectionURL)
        runtimeStore = HerdrRuntimeSelectionStore(url: url.deletingLastPathComponent().appendingPathComponent("runtime-selection.json"))
        runtimeSelection = runtimeStore.load()
        let connectionState: BessieConnectionState
        do {
            connectionState = try connectionStore.load()
        } catch {
            BessieDiagnosticLog.append("Connections load failed: \(String(reflecting: error))")
            connectionState = BessieConnectionState()
        }
        connections = connectionState.connections
        selectedConnectionID = connectionState.selectedConnectionID
        connectionError = nil
        onboarding.completed = state?.firstRealTerminalCompletionVersion == BessiePresentationState.firstRealTerminalCompletionVersion
        if onboarding.completed { onboarding.step = .terminal }
        BessieDiagnosticLog.append("Connections selected=\(selectedConnectionID) count=\(connections.count)")
    }

    private func persist() {
        try? store.save(BessiePresentationState(
            lastWorkspaceID: lastWorkspaceIDByConnectionID[BessieConnectionDefinition.localBessie.id] ?? legacyLastWorkspaceID,
            lastWorkspaceIDByConnectionID: lastWorkspaceIDByConnectionID,
            preferences: preferences,
            firstRealTerminalCompletionVersion: onboarding.completed ? BessiePresentationState.firstRealTerminalCompletionVersion : nil
        ))
    }

    var lastWorkspaceID: String? {
        lastWorkspaceID(for: selectedConnectionID)
    }

    func recordLastWorkspace(_ id: String?) {
        recordLastWorkspace(id, connectionID: selectedConnectionID)
    }

    func lastWorkspaceID(for connectionID: String) -> String? {
        lastWorkspaceIDByConnectionID[connectionID]
            ?? (connectionID == BessieConnectionDefinition.localBessie.id ? legacyLastWorkspaceID : nil)
    }

    func recordLastWorkspace(_ id: String?, connectionID: String) {
        lastWorkspaceIDByConnectionID[connectionID] = id
        persist()
    }

    var selectedConnection: BessieConnectionDefinition {
        connections.first { $0.id == selectedConnectionID } ?? .localBessie
    }

    func selectConnection(_ id: String) {
        guard connections.contains(where: { $0.id == id }) else { return }
        selectedConnectionID = id
        connectionError = nil
        persistConnections()
    }

    @discardableResult
    func addConnection(name: String, sshHost: String, session: String?) -> Bool {
        do {
            let connection = try BessieConnectionDefinition(
                name: name,
                kind: .ssh,
                sshHost: sshHost,
                session: session
            ).validated()
            connections.append(connection)
            selectedConnectionID = connection.id
            connectionError = nil
            persistConnections()
            return true
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    func removeConnection(_ id: String) {
        guard id != BessieConnectionDefinition.localBessie.id else { return }
        connections.removeAll { $0.id == id }
        if selectedConnectionID == id { selectedConnectionID = BessieConnectionDefinition.localBessie.id }
        connectionError = nil
        persistConnections()
    }

    func clearConnectionError() { connectionError = nil }

    func selectRuntime(_ selection: HerdrRuntimeSelection) {
        do {
            try runtimeStore.save(selection)
            runtimePersistenceError = nil
            runtimeSelection = selection
        } catch {
            runtimePersistenceError = error.localizedDescription
        }
    }

    func runSetupAgain() { onboarding.runAgain(); persist() }

    func advanceSetup(runtimeReady: Bool, sessionReady: Bool, workspaceReady: Bool, terminalControllerReady: Bool) {
        onboarding.advance(runtimeReady: runtimeReady, sessionReady: sessionReady, workspaceReady: workspaceReady,
                           terminalControllerReady: terminalControllerReady)
        persist()
    }

    func terminalBecameReady() {
        onboarding.step = .terminal
        onboarding.advance(runtimeReady: true, sessionReady: true, workspaceReady: true, terminalControllerReady: true)
        persist()
    }

    private func persistConnections() {
        try? connectionStore.save(BessieConnectionState(
            selectedConnectionID: selectedConnectionID,
            connections: connections
        ))
    }

}

@MainActor
enum BessieAppIconController {
    static func apply(_ icon: BessieAppIcon) {
        let resource = icon == .dark ? "BessieDark" : "BessieLight"
        guard let url = BessieResources.url(forResource: resource, withExtension: "icns"),
              let image = NSImage(contentsOf: url)
        else { return }
        NSApplication.shared.applicationIconImage = image
        BessieDiagnosticLog.append("App icon=\(icon.rawValue)")
    }
}

struct BessieSettingsView: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @State private var showAddConnection = false
    @State private var connectionName = ""
    @State private var sshHost = ""
    @State private var herdrSession = ""
    let embedded: Bool
    let runtimeDiagnostic: RuntimeDiagnosticSnapshot?

    init(embedded: Bool = false, runtimeDiagnostic: RuntimeDiagnosticSnapshot? = nil) {
        self.embedded = embedded
        self.runtimeDiagnostic = runtimeDiagnostic
    }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    BessieTopBar(title: "Settings") {
                        Button("Reset to defaults") { model.preferences = BessiePreferences() }
                            .buttonStyle(BessieQuietButtonStyle())
                    }
                    settingsScroll
                }
            } else {
                ZStack {
                    BessieCowprintTexture(base: BessieDesign.window, crop: .settings)
                    settingsScroll
                        .padding(9)
                        .bessieSurface(base: BessieDesign.background, crop: .settings)
                }
                .frame(width: 720, height: 620)
            }
        }
        .preferredColorScheme(.dark)
        .tint(BessieDesign.strong)
        .navigationTitle("Bessie settings")
        .task { notifications.refreshAuthorization() }
        .sheet(isPresented: $showAddConnection) { addConnectionSheet }
    }

    private var settingsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BessieSectionLabel("CONNECTIONS")
                    .padding(.bottom, 7)

                VStack(spacing: 0) {
                    ForEach(model.connections) { connection in
                        connectionRow(connection)
                        if connection.id != model.connections.last?.id {
                            Divider().overlay(BessieDesign.border)
                        }
                    }
                }
                .background(BessieDesign.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                        .stroke(BessieDesign.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))

                HStack {
                    if let error = model.connectionError {
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(BessieDesign.subtle)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Add SSH connection") {
                        connectionName = ""
                        sshHost = ""
                        herdrSession = ""
                        model.clearConnectionError()
                        showAddConnection = true
                    }
                    .buttonStyle(BessieSecondaryButtonStyle())
                }
                .padding(.top, 10)

                BessieSectionLabel("APPEARANCE")
                    .padding(.top, 28)
                    .padding(.bottom, 7)

                BessieSettingRow(label: "App icon", hint: "Used in the Dock and app switcher.") {
                    Picker("App icon", selection: $model.preferences.appIcon) {
                        ForEach(BessieAppIcon.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                BessieSectionLabel("COWPRINT")
                    .padding(.top, 28)
                    .padding(.bottom, 7)

                BessieSettingRow(label: "Contrast") {
                    Slider(value: $model.preferences.cowPrintIntensity, in: 0.015...0.10)
                        .frame(width: 220)
                        .accessibilityLabel("Cowprint contrast")
                }

                BessieSettingRow(label: "Cowprint motion") {
                    Toggle("", isOn: $model.preferences.cowPrintMotion)
                        .labelsHidden()
                        .accessibilityLabel("Cowprint motion")
                        .toggleStyle(.switch)
                }

                BessieSectionLabel("TERMINAL")
                    .padding(.top, 28)
                    .padding(.bottom, 7)

                BessieSettingRow(label: "Font size") {
                    Stepper("\(Int(model.preferences.terminalFontSize)) pt", value: $model.preferences.terminalFontSize, in: 10...24)
                        .font(.system(size: 11, design: .monospaced))
                        .accessibilityLabel("Terminal font size")
                        .accessibilityValue("\(Int(model.preferences.terminalFontSize)) points")
                }

                BessieSettingRow(label: "Pane spacing") {
                    Stepper("\(Int(model.preferences.paneGap)) pt", value: $model.preferences.paneGap, in: 0...16)
                        .font(.system(size: 11, design: .monospaced))
                        .accessibilityLabel("Pane spacing")
                        .accessibilityValue("\(Int(model.preferences.paneGap)) points")
                }

                BessieSectionLabel("NOTIFICATIONS")
                    .padding(.top, 28)
                    .padding(.bottom, 7)

                BessieSettingRow(label: "Notify me", hint: "Only when the pane isn't active.") {
                    Picker("Notify me", selection: $model.preferences.notifications) {
                        ForEach(BessieNotifications.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                if model.preferences.notifications != .off {
                    BessieSettingRow(label: "Permission") {
                        notificationPermissionControl
                    }
                    if let error = notifications.authorizationError {
                        Text(error)
                            .font(.system(size: 11.5))
                            .foregroundStyle(BessieDesign.strong)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }

                BessieSectionLabel("STARTUP")
                    .padding(.top, 28)
                    .padding(.bottom, 7)

                BessieSettingRow(label: "On startup") {
                    Picker("On startup", selection: $model.preferences.startupBehavior) {
                        ForEach(BessieStartupBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                BessieSectionLabel("VERSIONS")
                    .padding(.top, 28)
                    .padding(.bottom, 7)

                VStack(spacing: 0) {
                    BessieDiagnosticRow(
                        label: runtimeDiagnostic == nil ? "Required Herdr" : "Active Herdr",
                        value: runtimeDiagnostic.map {
                            "\($0.observedVersion ?? "Unknown") · protocol \($0.observedProtocol.map(String.init) ?? "Unknown") · \($0.runtime?.source.rawValue ?? "unresolved")"
                        } ?? "\(BessieCompatibility.herdrVersion) · protocol \(BessieCompatibility.protocolVersion)"
                    )
                    Divider().overlay(BessieDesign.border)
                    BessieDiagnosticRow(label: "Terminal", value: "libghostty 1.3.2")
                }
                .background(BessieDesign.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                        .stroke(BessieDesign.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))

                RuntimeSettingsView()
                    .padding(.top, 28)


            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .background(Color.clear)
    }

    private func connectionRow(_ connection: BessieConnectionDefinition) -> some View {
        HStack(spacing: 12) {
            Image(systemName: connection.kind == .local ? "laptopcomputer" : "network")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(BessieDesign.strong)
                Text(connection.detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(BessieDesign.subtle)
            }
            Spacer()
            Text("INCLUDED")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(BessieDesign.strong)
            if connection.kind == .ssh {
                Button { model.removeConnection(connection.id) } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BessieDesign.subtle)
                .accessibilityLabel("Remove \(connection.name)")
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 54)
    }

    private var addConnectionSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            BessieSectionLabel("NEW SSH CONNECTION")
                .padding(.bottom, 18)
            connectionField("Name", placeholder: "Hermes VPS", text: $connectionName)
            connectionField("SSH host", placeholder: "hermes", text: $sshHost)
                .padding(.top, 14)
            connectionField("Herdr session", placeholder: "default", text: $herdrSession)
                .padding(.top, 14)
            Text("Uses your OpenSSH config and key agent. Bessie never stores a password. Leave the session blank for Herdr's default session.")
                .font(.system(size: 10.5))
                .lineSpacing(2)
                .foregroundStyle(BessieDesign.subtle)
                .padding(.top, 12)
            if let error = model.connectionError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.strong)
                    .padding(.top, 10)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { showAddConnection = false }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Add and connect") {
                    if model.addConnection(name: connectionName, sshHost: sshHost, session: herdrSession) {
                        showAddConnection = false
                    }
                }
                .buttonStyle(BessiePrimaryButtonStyle())
            }
            .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 460)
        .background(BessieDesign.background)
        .preferredColorScheme(.dark)
    }

    private func connectionField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BessieDesign.subtle)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(BessieDesign.inset)
                .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        }
    }

    @ViewBuilder private var notificationPermissionControl: some View {
        switch notifications.authorizationStatus {
        case .notDetermined:
            Button("Allow notifications") { notifications.requestAuthorization() }
                .buttonStyle(BessieSecondaryButtonStyle())
        case .denied:
            Button("Open System Settings") { notifications.openSystemSettings() }
                .buttonStyle(BessieSecondaryButtonStyle())
        case .authorized, .provisional, .ephemeral:
            Text("Allowed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
        @unknown default:
            Text("Unavailable")
                .font(.system(size: 11))
                .foregroundStyle(BessieDesign.subtle)
        }
    }
}

private struct BessieSettingRow<Control: View>: View {
    let label: String
    let hint: String?
    @ViewBuilder let control: Control

    init(label: String, hint: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.hint = hint
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BessieDesign.strong)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11.5))
                        .lineSpacing(2)
                        .foregroundStyle(BessieDesign.subtle)
                        .frame(maxWidth: 360, alignment: .leading)
                }
            }
            Spacer(minLength: 20)
            control
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(BessieDesign.border).frame(height: 1) }
    }
}

private struct BessieDiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(BessieDesign.subtle)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
    }
}

private extension BessieStartupBehavior {
    var title: String { switch self { case .lastWorkspace: "Reopen last workspace"; case .workspaceChooser: "Show workspaces" } }
}

private extension BessieAppIcon {
    var title: String { switch self { case .dark: "Dark"; case .light: "Light" } }
}

private extension BessieNotifications {
    var title: String {
        switch self {
        case .off: "Off"
        case .blockedOnly: "When work needs me"
        case .blockedAndDone: "Needs me and done"
        }
    }
}

struct BessieWindowSnapshotProbe: NSViewRepresentable {
    final class Coordinator { var captured = false }
    let role: String

    init(role: String = "main") {
        self.role = role
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let preview = ProcessInfo.processInfo.environment["BESSIE_DESIGN_PREVIEW"]?.lowercased()
        let capturesSheet = preview == "new-process"
            || preview == "command-palette"
            || preview == "project-capture"
            || preview == "project-launch-review"
        guard ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_PATH"] != nil,
              ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_TRIGGER"] == nil,
              (capturesSheet ? role == "sheet" : role == "main")
        else { return view }
        let delay = Double(ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_DELAY"] ?? "3") ?? 3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !context.coordinator.captured else { return }
            context.coordinator.captured = true
            BessieWindowSnapshot.capture(window: view.window)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
enum BessieWindowSnapshot {
    static func captureWhenReady(
        registry: TerminalControllerRegistry,
        paneIDs: Set<String>,
        remainingAttempts: Int = 60,
        consecutiveReadyChecks: Int = 0
    ) {
        let visible = paneIDs.compactMap { registry.controllers[$0] }
        let ready = visible.count >= 2 && visible.allSatisfy { controller in
            if case .ready = controller.status { return true }
            return false
        }
        if ready, consecutiveReadyChecks >= 3 {
            capture()
        } else if remainingAttempts > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                captureWhenReady(
                    registry: registry,
                    paneIDs: paneIDs,
                    remainingAttempts: remainingAttempts - 1,
                    consecutiveReadyChecks: ready ? consecutiveReadyChecks + 1 : 0
                )
            }
        }
    }

    static func capture(window requestedWindow: NSWindow? = nil) {
        guard let path = ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_PATH"],
              let window = requestedWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
              let content = window.contentView,
              content.bounds.width > 0,
              content.bounds.height > 0
        else { return }

        content.layoutSubtreeIfNeeded()
        content.displayIfNeeded()
        let bitmap: NSBitmapImageRep?
        if let image = captureWindowImage(windowNumber: window.windowNumber),
           image.width >= Int(content.bounds.width.rounded(.down)),
           image.height >= Int(content.bounds.height.rounded(.down)) {
            bitmap = NSBitmapImageRep(cgImage: image)
        } else if let cached = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.displayIfNeeded()
            content.cacheDisplay(in: content.bounds, to: cached)
            bitmap = cached
        } else {
            bitmap = nil
        }
        guard let png = bitmap?.representation(using: .png, properties: [:]) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url, options: .atomic)
        BessieDiagnosticLog.append("Window snapshot path=\(path) width=\(Int(content.bounds.width)) height=\(Int(content.bounds.height))")
    }

    private static func captureWindowImage(windowNumber: Int) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        return capture(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            UInt32(windowNumber),
            (CGWindowImageOption.boundsIgnoreFraming.union(.bestResolution)).rawValue
        )?.takeRetainedValue()
    }
}
