import BessieCore
import SwiftUI

struct OnboardingView: View {
    @Environment(\.openSettings) private var openSettings
    let state: OnboardingState
    let connected: Bool
    let hasWorkspace: Bool
    let terminalControllerReady: Bool
    let createWorkspace: () -> Void
    let continueSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SET UP BESSIE").font(.system(size: 10, weight: .semibold)).foregroundStyle(BessieDesign.subtle)
            Text(title).font(.system(size: 28, weight: .medium))
            Text(detail).foregroundStyle(BessieDesign.text).frame(maxWidth: 520, alignment: .leading)
            Text("Step \(state.step.rawValue) of 5").font(.system(size: 10, design: .monospaced)).foregroundStyle(BessieDesign.subtle)
            if state.step == .workspace && !hasWorkspace {
                Button("Create workspace", action: createWorkspace).buttonStyle(BessiePrimaryButtonStyle())
            } else {
                Button(buttonTitle, action: continueSetup).buttonStyle(BessiePrimaryButtonStyle()).disabled(!canAdvance)
            }
            DisclosureGroup("Use Herdr on another Mac over SSH") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Remote Herdr and its session must already be running. You can add and select the connection in Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(BessieDesign.subtle)
                    Button("Open connection settings") { openSettings() }
                        .buttonStyle(BessieSecondaryButtonStyle())
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: 520, alignment: .leading)
        }.padding(40).frame(maxWidth: 680, alignment: .leading).bessieSurface(base: BessieDesign.background, crop: .connect)
    }

    private var title: String { switch state.step {
    case .welcome: "Welcome to Bessie"; case .runtime: "Verify the included runtime"; case .session: "Open the Bessie session";
    case .workspace: "Choose a workspace"; case .terminal: "Open a real terminal" } }
    private var detail: String { switch state.step {
    case .welcome: "Herdr owns your work, sessions, and terminal processes. Closing Bessie leaves them running."
    case .runtime: "Bessie checks its included, compatible Herdr runtime. Nothing is downloaded."
    case .session: "Bessie starts or reuses only the named bessie session."
    case .workspace: "Create or open a Herdr workspace to continue."
    case .terminal: "Setup finishes only after the terminal controller and libghostty surface are ready." } }
    private var buttonTitle: String { state.step == .terminal ? "Finish" : "Continue" }
    private var canAdvance: Bool { switch state.step { case .welcome: true; case .runtime, .session: connected; case .workspace: hasWorkspace; case .terminal: terminalControllerReady } }
}
