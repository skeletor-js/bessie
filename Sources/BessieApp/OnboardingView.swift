import AppKit
import BessieCore
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @EnvironmentObject private var settings: BessieSettingsModel
    @EnvironmentObject private var notifications: BessieNotificationCoordinator
    @ObservedObject var projects: ProjectsViewModel
    let state: OnboardingState
    let connected: Bool
    let completionAvailable: Bool
    let connectionError: String?
    @Binding var path: String
    let continueSetup: () -> Void
    let finishSetup: () -> Void
    let cancelSetup: () -> Void
    @State private var selectedPolicy: BessieNotifications = .blockedOnly
    @FocusState private var pathFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepRail
            ScrollView {
                VStack {
                    Spacer(minLength: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(heading)
                            .font(.system(size: 22, weight: .medium))
                            .tracking(-0.44)
                            .foregroundStyle(BessieDesign.strong)
                            .accessibilityAddTraits(.isHeader)
                        Text(lead)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(BessieDesign.subtle)
                            .padding(.top, 9)
                            .padding(.bottom, 26)
                        content
                        if let error = settings.onboardingCompletionError {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundStyle(BessieDesign.strong)
                                .padding(.top, 12)
                                .accessibilityLabel("Setup error, \(error)")
                        } else if let connectionError {
                            Text(connectionError)
                                .font(.system(size: 11.5))
                                .foregroundStyle(BessieDesign.strong)
                                .padding(.top, 12)
                                .accessibilityLabel("Connection error, \(connectionError)")
                        }
                        actions
                    }
                    .frame(width: 540, alignment: .leading)
                    Spacer(minLength: 44)
                }
                .frame(maxWidth: .infinity, minHeight: 726)
                .padding(.horizontal, 44)
                .offset(y: designVerticalOffset)
            }
            .background(onboardingBackground)
        }
        .background(onboardingBackground)
        .bessieOnboardingWindowTitle(BessieOnboardingWindowChrome.welcomeTitle)
        .task {
            projects.load()
            notifications.refreshAuthorization()
            selectedPolicy = settings.preferences.notifications
            pathFocused = state.step == .connect
        }
        .onExitCommand(perform: cancelSetup)
    }

    private var designVerticalOffset: CGFloat {
        guard ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] != nil else { return 0 }
        return switch state.step {
        case .connect: 28
        case .howItWorks, .notifications: 30
        case .readTheRail: 31
        }
    }

    private var onboardingBackground: BessieSemanticColor { BessieDesign.background }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                BessieIconView(icon: .cow, size: 16)
                    .foregroundStyle(BessieDesign.accent)
                Text("Bessie").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(BessieDesign.strong)
            VStack(spacing: 3) {
                ForEach(OnboardingState.Step.allCases, id: \.rawValue) { step in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(step.rawValue < state.step.rawValue ? BessieDesign.done : BessieSemanticColor.clear)
                                .stroke(
                                    step.rawValue < state.step.rawValue
                                        ? BessieDesign.done
                                        : step == state.step ? BessieDesign.accent : BessieDesign.borderStrong,
                                    lineWidth: 1.5
                                )
                            if step.rawValue < state.step.rawValue {
                                BessieIconView(icon: .check, size: 12)
                                    .foregroundStyle(BessieDesign.background)
                            } else {
                                Text("\(step.rawValue)").font(.system(size: 11))
                            }
                        }
                        .frame(width: 21, height: 21)
                        Text(title(step)).font(.system(size: 13, weight: step == state.step ? .medium : .regular))
                        Spacer()
                    }
                    .foregroundStyle(
                        step == state.step
                            ? BessieDesign.strong
                            : step.rawValue < state.step.rawValue ? BessieDesign.text : BessieDesign.subtle
                    )
                    .padding(.horizontal, 11)
                    .frame(height: 41)
                    .background(step == state.step ? BessieDesign.selected : BessieSemanticColor.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(stepAccessibilityLabel(step))
                }
            }
            .padding(.top, 30)
            Spacer()
            if settings.canCancelSetupBeforeMaterialization {
                Button("Cancel Setup", action: cancelSetup)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(BessieDesign.subtle)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 32)
        .frame(width: 312, alignment: .leading)
        .background(BessieDesign.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(BessieDesign.border).frame(width: 1) }
    }

    @ViewBuilder private var content: some View {
        switch state.step {
        case .connect: connectContent
        case .howItWorks: howItWorksContent
        case .readTheRail: railLegend
        case .notifications: notificationContent
        }
    }

    private var connectContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let local = settings.enabledConnections.first(where: { $0.kind == .local }) {
                connectionCard(connection: local, icon: .desktop, title: "Local herd")
            }
            remoteConnectionCard
            if settings.selectedConnection.kind == .ssh {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Workspace folder").font(.system(size: 11.5, weight: .medium)).foregroundStyle(BessieDesign.strong)
                    TextField("/absolute/remote/folder", text: $path)
                        .focused($pathFocused)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Initial workspace folder")
                }
                .padding(.top, 4)
            }
        }
    }

    private func connectionCard(connection: BessieConnectionDefinition, icon: BessieIcon, title: String) -> some View {
        let selected = settings.selectedConnectionID == connection.id
        return Button {
            settings.selectConnection(connection.id)
            if connection.kind == .local { chooseFolder() }
        } label: {
            HStack(spacing: 13) {
                cardIcon(icon)
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(BessieDesign.strong)
                Spacer()
                if selected { BessieIconView(icon: .check, size: 18).foregroundStyle(BessieDesign.accent) }
            }
            .padding(.horizontal, 15).frame(height: 70)
            .background(BessieDesign.panel)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(selected ? BessieDesign.accent : BessieDesign.border, lineWidth: 1) }
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(selected ? BessieDesign.accentSoft : BessieSemanticColor.clear, lineWidth: 3) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var remoteConnectionCard: some View {
        let remotes = settings.enabledConnections.filter { $0.kind == .ssh }
        let selected = settings.selectedConnection.kind == .ssh
        return Group {
            if remotes.isEmpty {
                Button { settings.requestAddConnection() } label: { remoteConnectionLabel(selected: false) }
                    .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(remotes) { connection in Button(connection.name) { settings.selectConnection(connection.id) } }
                } label: {
                    remoteConnectionLabel(selected: selected)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .frame(height: 66)
        .background(BessieDesign.panel)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(selected ? BessieDesign.accent : BessieDesign.border, lineWidth: 1) }
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(selected ? BessieDesign.accentSoft : BessieSemanticColor.clear, lineWidth: 3) }
        .accessibilityLabel(selected ? "Remote herd, \(settings.selectedConnection.name)" : "Join a remote herd")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func remoteConnectionLabel(selected: Bool) -> some View {
        HStack(spacing: 13) {
            cardIcon(.cloud)
            Text(selected ? settings.selectedConnection.name : "Join a remote herd")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            Spacer()
            BessieIconView(icon: selected ? .check : .plus, size: selected ? 18 : 13)
                .foregroundStyle(selected ? BessieDesign.accent : BessieDesign.subtle)
        }
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cardIcon(_ icon: BessieIcon) -> some View {
        BessieIconView(icon: icon, size: 16).foregroundStyle(BessieDesign.accent)
            .frame(width: 38, height: 38).background(BessieDesign.inset).clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private var howItWorksContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            callout(icon: .power, background: BessieDesign.panel) {
                Text("Close Bessie and every agent keeps working. Open it again and the same panes are there, mid-sentence. Nothing you start here dies with the window.")
            }
            Text("HOW THE PIECES NEST")
                .font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(BessieDesign.faint)
                .padding(.top, 16).padding(.bottom, 11)
            VStack(spacing: 9) {
                nestingRow("Herd", "one machine running Herdr — the local one, or a remote over ssh", indent: 0)
                nestingRow("Workspace", "a folder and the session working in it", indent: 14)
                nestingRow("Tab", "one arrangement of panes inside that workspace", indent: 28)
                nestingRow("Pane", "a real terminal · a shell, or an agent like Claude or Codex", indent: 42)
            }
            callout(icon: .stack, background: BessieDesign.inset) {
                (Text("A project is a recipe, not a place. ").fontWeight(.medium).foregroundStyle(BessieDesign.strong)
                    + Text("It remembers a workspace's tabs, panes and the command each pane runs, so tomorrow you rebuild the whole arrangement in one click instead of keeping empty shells open."))
            }
            .padding(.top, 18)
        }
    }

    private func nestingRow(_ name: String, _ detail: String, indent: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(BessieDesign.strong).frame(width: 92, alignment: .leading)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(BessieDesign.subtle).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: 19).padding(.leading, indent)
    }

    private func callout<Content: View>(icon: BessieIcon, background: BessieSemanticColor, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 11) {
            BessieIconView(icon: icon, size: 16).foregroundStyle(icon == .power ? BessieDesign.accent : BessieDesign.subtle)
            content().font(.system(size: 12)).lineSpacing(5).foregroundStyle(BessieDesign.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, icon == .power ? 16 : 15.5)
        .background(background)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(BessieDesign.border, lineWidth: 1) }
    }

    private var railLegend: some View {
        VStack(spacing: 13) {
            legendRow(.needsYou, "Needs you", "waiting on a human · the only thing that interrupts")
            legendRow(.working, "Working", "thinking, running tools, making progress")
            legendRow(.settled, "Settled", "done or idle — nothing moving, nothing asked")
            legendRow(.unknown, "Unknown", "Herdr cannot classify it · never read as attention")
        }
        .padding(.horizontal, 18).padding(.vertical, 18.5).background(BessieDesign.panel)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(BessieDesign.border, lineWidth: 1) }
    }

    private func legendRow(_ geometry: OnboardingStateMark.Geometry, _ name: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            BessieStatusGlyph(state: geometry.semanticState)
            Text(name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(BessieDesign.strong).frame(width: 96, alignment: .leading)
            Text(detail).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(BessieDesign.faint)
            Spacer(minLength: 0)
        }.accessibilityElement(children: .combine)
    }

    private var notificationContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notify me").font(.system(size: 11.5, weight: .medium)).foregroundStyle(BessieDesign.strong)
            HStack(spacing: 2) {
                ForEach(BessieNotifications.allCases, id: \.self) { policy in
                    Button(policy.title) { selectedPolicy = policy }
                        .buttonStyle(OnboardingSegmentButtonStyle(
                            selected: selectedPolicy == policy,
                            width: segmentWidth(policy)
                        ))
                        .accessibilityValue(selectedPolicy == policy ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selectedPolicy == policy ? .isSelected : [])
                }
            }
            .padding(2)
            .background(BessieDesign.inset)
            .overlay { RoundedRectangle(cornerRadius: 3).stroke(BessieDesign.border, lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .padding(.top, 5)
            Text("Working never interrupts.").font(.system(size: 10.5)).foregroundStyle(BessieDesign.faint).padding(.top, 5)
            HStack(spacing: 12) {
                cardIcon(.bell)
                Text("macOS notification permission").font(.system(size: 13, weight: .medium)).foregroundStyle(BessieDesign.strong)
                Spacer()
                notificationPermissionControl
            }
            .padding(.horizontal, 15).frame(height: 64).background(BessieDesign.panel)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(BessieDesign.border, lineWidth: 1) }
            .padding(.top, 14)
        }
    }

    @ViewBuilder private var notificationPermissionControl: some View {
        switch designNotificationAuthorizationStatus ?? notifications.authorizationStatus {
        case .notDetermined:
            Button("Allow") { notifications.requestAuthorization() }
                .buttonStyle(OnboardingPrimaryButtonStyle(width: 49))
        case .denied:
            Button("System Settings") { notifications.openNotificationSettings() }.buttonStyle(OnboardingPrimaryButtonStyle())
        case .authorized, .provisional, .ephemeral:
            HStack(spacing: 5) {
                BessieIconView(icon: .check, size: 12)
                Text("Allowed")
            }.font(.system(size: 11.5, weight: .medium))
        @unknown default:
            Text("Unavailable").font(.system(size: 11.5)).foregroundStyle(BessieDesign.subtle)
        }
    }

    private var designNotificationAuthorizationStatus: UNAuthorizationStatus? {
        ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "13" ? .notDetermined : nil
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if state.step == .notifications {
                Button("Finish and open terminal") {
                    settings.preferences.notifications = selectedPolicy
                    finishSetup()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle(width: 155)).disabled(!completionAvailable)
                Button("Skip", action: finishSetup).buttonStyle(.plain).disabled(!completionAvailable)
            } else {
                Button("Continue", action: continueSetup)
                .buttonStyle(OnboardingPrimaryButtonStyle(width: 72)).disabled(!canContinue)
                if state.step != .connect { Button("Back") { settings.goBackInSetup() }.buttonStyle(.plain) }
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.top, 30)
    }

    private var canContinue: Bool {
        guard state.step == .connect else { return true }
        guard connected else { return false }
        do { _ = try OnboardingPathValidator.absolute(path); return true } catch { return false }
    }

    private func stepAccessibilityLabel(_ step: OnboardingState.Step) -> String {
        if step.rawValue < state.step.rawValue { return "\(title(step)), completed" }
        if step == state.step { return "Step \(step.rawValue), \(title(step)), current" }
        return "Step \(step.rawValue), \(title(step)), upcoming"
    }

    private var heading: String {
        switch state.step {
        case .connect: "Select your herd"
        case .howItWorks: "Bessie is a window onto Herdr"
        case .readTheRail: "Four states, and where they live"
        case .notifications: "How should agents reach you?"
        }
    }

    private var lead: String {
        switch state.step {
        case .connect: "Bessie ships with its own Herdr — the local herd is already running. Herdr keeps your workspaces, panes and processes alive whether or not Bessie is open."
        case .howItWorks: "Herdr runs the terminals. Bessie draws them, watches them and tells you who needs a human — it never owns the processes, which is why quitting Bessie is safe."
        case .readTheRail: "Every pane reports one of four states, and each one is a different shape — so a glance at the rail tells you who is stuck, who is busy and who is finished. Clicking a row takes you into that pane."
        case .notifications: "Bessie sits in the menu bar and sends a push notification when an agent needs a human — the only way it can reach you when you are somewhere else."
        }
    }

    private func title(_ step: OnboardingState.Step) -> String {
        switch step { case .connect: "Connect"; case .howItWorks: "How it works"; case .readTheRail: "Read the rail"; case .notifications: "Notifications" }
    }

    private func segmentWidth(_ policy: BessieNotifications) -> CGFloat {
        switch policy {
        case .off: 35
        case .blockedOnly: 134
        case .blockedAndDone: 137
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK { path = panel.url?.standardizedFileURL.path ?? path }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var width: CGFloat?

    init(width: CGFloat? = nil) {
        self.width = width
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, width == nil ? 9.5 : 0)
            .frame(width: width)
            .frame(height: 28)
            .foregroundStyle(BessieDesign.accentForeground)
            .background(configuration.isPressed ? BessieDesign.done : BessieDesign.accent)
            .clipShape(RoundedRectangle(cornerRadius: BessieDesign.controlRadius))
    }
}

private struct OnboardingSegmentButtonStyle: ButtonStyle {
    let selected: Bool
    let width: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(BessieDesign.strong)
            .frame(width: width, height: 23)
            .background(selected ? BessieDesign.panel : BessieSemanticColor.clear)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private enum OnboardingStateMark {
    enum Geometry { case needsYou, working, settled, unknown }
}

private extension OnboardingStateMark.Geometry {
    var semanticState: AgentSemanticState {
        switch self {
        case .needsYou: .blocked
        case .working: .working
        case .settled: .done
        case .unknown: .unknown
        }
    }
}
