import AppKit
import BessieCore
import SwiftUI

struct TroubleView: View {
    let diagnostic: RuntimeDiagnosticSnapshot
    let retry: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trouble").font(.system(size: 28, weight: .medium))
            Text(message).foregroundStyle(BessieDesign.text)
            Group {
                fact("Runtime", diagnostic.runtime?.source.rawValue ?? "Unresolved")
                fact("Path", diagnostic.runtime?.url.path ?? "Unavailable")
                fact("Version", diagnostic.observedVersion ?? "Unknown")
                fact("Protocol", diagnostic.observedProtocol.map(String.init) ?? "Unknown")
                fact("Session", diagnostic.session)
                fact("API", diagnostic.apiHealthy ? "Healthy" : "Unavailable")
                fact("Terminal controller", diagnostic.terminalControllerHealthy ? "Healthy" : "Unavailable")
            }
            HStack {
                ForEach(diagnostic.availableActions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }.padding(32).bessieSurface(base: BessieDesign.background, crop: .connect)
    }

    private var message: String {
        diagnostic.finding == .bundledIntegrity ? "This copy of Bessie is damaged. Reinstall Bessie from a trusted package." : "Bessie could not finish setup. The facts below can help identify the failure."
    }
    private func fact(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(BessieDesign.subtle); Spacer(); Text(value).font(.system(size: 11, design: .monospaced)).lineLimit(1) }
    }

    @ViewBuilder
    private func actionButton(_ action: SetupAction) -> some View {
        switch action {
        case .retry:
            Button("Try again", action: retry).buttonStyle(BessiePrimaryButtonStyle())
        case .revealRuntime:
            Button("Show in Finder") {
                guard let url = diagnostic.runtimeRevealURL() else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }.buttonStyle(BessieSecondaryButtonStyle())
        case .copyReport:
            Button("Copy report") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(diagnostic.sanitizedReport, forType: .string)
            }.buttonStyle(BessieSecondaryButtonStyle())
        case .openSettings:
            Button("Open Settings") { openSettings() }.buttonStyle(BessieSecondaryButtonStyle())
        }
    }
}
