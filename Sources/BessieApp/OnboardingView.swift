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
    @Binding var setupConnectionID: String?
    @State private var showAddRemote = false
    @State private var remoteName = ""
    @State private var remoteHost = ""
    @State private var remoteSession = ""
    @FocusState private var pathFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            stepRail
            ScrollView {
                VStack {
                    Spacer(minLength: 44)
                    OnboardingStepRegion(initialOffset: 12) {
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
                    }
                    .id(state.step)
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
            if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] != nil,
               setupConnectionID == nil {
                setupConnectionID = settings.selectedConnectionID
            }
            pathFocused = state.step == .connect
        }
        .onChange(of: state.step) { _, step in
            pathFocused = step == .connect
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: stepAccessibilityLabel(step),
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
        .sheet(isPresented: $showAddRemote) { addRemoteSheet }
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
            BessiePhosphorCow(size: 19)
                .foregroundStyle(BessieDesign.strong)
                .accessibilityLabel("Bessie")
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
        VStack(alignment: .leading, spacing: 12) {
            if let local = settings.connections.first(where: { $0.kind == .local }) {
                connectionCard(
                    connection: local,
                    icon: .desktop,
                    title: "This Mac",
                    subtitle: "Use the Herdr runtime on this Mac"
                )
            }
            remoteConnectionCard
            if selectedSetupConnection?.kind == .local {
                localFolderSelection
            } else if selectedSetupConnection?.kind == .ssh {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Remote workspace folder").font(.system(size: 11.5, weight: .medium)).foregroundStyle(BessieDesign.strong)
                    TextField("/absolute/remote/folder", text: $path)
                        .focused($pathFocused)
                        .textFieldStyle(.roundedBorder)
                        .tint(BessieDesign.insertionPoint)
                        .accessibilityLabel("Initial remote workspace folder")
                }
                .padding(.top, 4)
            }
        }
    }

    private var selectedSetupConnection: BessieConnectionDefinition? {
        setupConnectionID.flatMap { id in settings.connections.first(where: { $0.id == id }) }
    }

    private var localFolderSelection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Workspace folder")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            HStack(spacing: 10) {
                BessieIconView(icon: .folderOpen, size: 15)
                    .foregroundStyle(BessieDesign.subtle)
                Text(path.isEmpty ? "No folder selected" : path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(path.isEmpty ? BessieDesign.faint : BessieDesign.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button(path.isEmpty ? "Choose Folder…" : "Change…") { chooseFolder() }
                    .buttonStyle(BessieSecondaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(BessieDesign.inset)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(BessieDesign.border, lineWidth: 1) }
        }
        .padding(.top, 4)
    }

    private func connectionCard(
        connection: BessieConnectionDefinition,
        icon: BessieIcon,
        title: String,
        subtitle: String
    ) -> some View {
        let selected = setupConnectionID == connection.id
        return Button {
            chooseConnection(connection)
        } label: {
            HStack(spacing: 13) {
                cardIcon(icon)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BessieDesign.strong)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(BessieDesign.subtle)
                }
                Spacer()
                if selected { BessieIconView(icon: .check, size: 18).foregroundStyle(BessieDesign.accent) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(height: 76)
            .background(BessieDesign.panel)
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(selected ? BessieDesign.activeBorder : BessieDesign.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var remoteConnectionCard: some View {
        let remotes = settings.connections.filter { $0.kind == .ssh }
        let selected = selectedSetupConnection?.kind == .ssh
        return Group {
            if remotes.isEmpty {
                Button { prepareAddRemote() } label: { remoteConnectionLabel(selected: false) }
                    .buttonStyle(.plain)
            } else {
                Menu {
                    ForEach(remotes) { connection in
                        Button(connection.name) { chooseConnection(connection) }
                    }
                    Divider()
                    Button("Add Remote Herd…") { prepareAddRemote() }
                } label: {
                    remoteConnectionLabel(selected: selected)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .frame(height: 76)
        .background(BessieDesign.panel)
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(selected ? BessieDesign.activeBorder : BessieDesign.border, lineWidth: 1) }
        .accessibilityLabel(selected ? "Remote herd, \(selectedSetupConnection?.name ?? "selected")" : "Remote over SSH")
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func remoteConnectionLabel(selected: Bool) -> some View {
        HStack(spacing: 13) {
            cardIcon(.cloud)
            VStack(alignment: .leading, spacing: 3) {
                Text("Remote over SSH")
                if selected, let selectedSetupConnection {
                    Text(selectedSetupConnection.name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(BessieDesign.subtle)
                }
            }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BessieDesign.strong)
            Spacer()
            BessieIconView(icon: selected ? .check : .plus, size: selected ? 18 : 13)
                .foregroundStyle(selected ? BessieDesign.accent : BessieDesign.subtle)
        }
        .padding(.horizontal, 18)
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
            legendRow(.done, "Done", "finished work reported by Herdr")
            legendRow(.idle, "Idle", "not currently working or asking for input")
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
            }
            if state.canNavigateBack { Button("Back") { settings.goBackInSetup() }.buttonStyle(.plain) }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.top, 30)
    }

    private var canContinue: Bool {
        guard state.step == .connect else { return true }
        guard setupConnectionID != nil,
              setupConnectionID == settings.selectedConnectionID,
              connected
        else { return false }
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
        case .readTheRail: "Five states, and where they live"
        case .notifications: "How should agents reach you?"
        }
    }

    private var lead: String {
        switch state.step {
        case .connect: "Choose where Herdr runs, then choose the workspace Bessie should open first. You can use the bundled Herdr on this Mac or connect to a remote host over SSH."
        case .howItWorks: "Herdr runs the terminals. Bessie draws them, watches them and tells you who needs a human — it never owns the processes, which is why quitting Bessie is safe."
        case .readTheRail: "Every pane reports one of five states, and each one is a different shape — so a glance at the rail tells you who is stuck, who is busy, who is finished and who is idle. Clicking a row takes you into that pane."
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
        let panel = NSOpenPanel()
        panel.title = "Choose Your First Workspace"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true) }
        if panel.runModal() == .OK { path = panel.url?.standardizedFileURL.path ?? path }
    }

    private func chooseConnection(_ connection: BessieConnectionDefinition) {
        guard settings.selectConnectionForSetup(connection.id) else { return }
        if setupConnectionID != connection.id { path = "" }
        setupConnectionID = connection.id
        if connection.kind == .local { chooseFolder() }
        else { pathFocused = true }
    }

    private var addRemoteSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            BessieSectionLabel("ADD REMOTE HERD")
                .padding(.bottom, 18)
            remoteField("Name", placeholder: "Studio Mac", text: $remoteName)
            remoteField("SSH host", placeholder: "studio-mac", text: $remoteHost)
                .padding(.top, 14)
            remoteField("Herdr session", placeholder: "default", text: $remoteSession)
                .padding(.top, 14)
            Text("Use a Host alias from ~/.ssh/config. OpenSSH owns the destination, user, key, and agent. The Herdr session is optional.")
                .font(.system(size: 10.5))
                .lineSpacing(2)
                .foregroundStyle(BessieDesign.subtle)
                .padding(.top, 12)
            if let error = settings.connectionError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(BessieDesign.strong)
                    .padding(.top, 10)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { showAddRemote = false }
                    .buttonStyle(BessieSecondaryButtonStyle())
                Button("Add and connect") { addRemote() }
                    .buttonStyle(BessiePrimaryButtonStyle())
            }
            .padding(.top, 22)
        }
        .padding(28)
        .frame(width: 460)
        .background(BessieDesign.background)
        .preferredColorScheme(settings.preferences.appearance.preferredColorScheme)
    }

    private func remoteField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BessieDesign.subtle)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .tint(BessieDesign.insertionPoint)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(BessieDesign.inset)
                .overlay { Rectangle().stroke(BessieDesign.border, lineWidth: 1) }
        }
    }

    private func prepareAddRemote() {
        remoteName = ""
        remoteHost = ""
        remoteSession = ""
        settings.clearConnectionError()
        showAddRemote = true
    }

    private func addRemote() {
        guard settings.addConnection(name: remoteName, sshHost: remoteHost, session: remoteSession) else { return }
        setupConnectionID = settings.selectedConnectionID
        path = ""
        showAddRemote = false
        pathFocused = true
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

private struct OnboardingStepRegion<Content: View>: View {
    let initialOffset: CGFloat
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opacity = 0.0
    @State private var horizontalOffset: CGFloat

    init(initialOffset: CGFloat, @ViewBuilder content: () -> Content) {
        self.initialOffset = initialOffset
        self.content = content()
        _horizontalOffset = State(initialValue: initialOffset)
    }

    var body: some View {
        content
            .opacity(reduceMotion ? 1 : opacity)
            .offset(x: reduceMotion ? 0 : horizontalOffset)
            .task {
                guard !reduceMotion else {
                    opacity = 1
                    horizontalOffset = 0
                    return
                }
                opacity = 0
                horizontalOffset = initialOffset
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(BessieDesign.motionExplanatoryEaseOut) {
                    opacity = 1
                    horizontalOffset = 0
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                if shouldReduceMotion {
                    opacity = 1
                    horizontalOffset = 0
                }
            }
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
    enum Geometry { case needsYou, working, done, idle, unknown }
}

private extension OnboardingStateMark.Geometry {
    var semanticState: AgentSemanticState {
        switch self {
        case .needsYou: .blocked
        case .working: .working
        case .done: .done
        case .idle: .idle
        case .unknown: .unknown
        }
    }
}
