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
    @Published private(set) var lastWorkspaceID: String?
    private let store: BessiePresentationStore

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
        lastWorkspaceID = state?.lastWorkspaceID
    }

    private func persist() {
        try? store.save(BessiePresentationState(lastWorkspaceID: lastWorkspaceID, preferences: preferences))
    }

    func recordLastWorkspace(_ id: String?) { lastWorkspaceID = id; persist() }
}

struct BessieSettingsView: View {
    @EnvironmentObject private var model: BessieSettingsModel
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    let embedded: Bool

    init(embedded: Bool = false) {
        self.embedded = embedded
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
    }

    private var settingsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BessieSectionLabel("COWPRINT")
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
                    BessieDiagnosticRow(label: "Herdr", value: "0.7.5 · protocol 17")
                    Divider().overlay(BessieDesign.border)
                    BessieDiagnosticRow(label: "Terminal", value: "libghostty 1.3.2")
                }
                .background(BessieDesign.panel)
                .overlay {
                    RoundedRectangle(cornerRadius: BessieDesign.controlRadius)
                        .stroke(BessieDesign.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))


            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.top, 30)
            .padding(.bottom, 60)
        }
        .background(Color.clear)
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
        guard ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_PATH"] != nil,
              ProcessInfo.processInfo.environment["BESSIE_WINDOW_SNAPSHOT_TRIGGER"] == nil,
              (preview == "new-process" ? role == "sheet" : role == "main")
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
        if let image = captureWindowImage(windowNumber: window.windowNumber) {
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
