import AppKit
import BessieCore
import SwiftUI

struct TroubleView: View {
    let diagnostic: RuntimeDiagnosticSnapshot
    let retry: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack {
            HStack(spacing: BessieDesign.cardGap) {
                VStack(alignment: .leading, spacing: 0) {
                    BessieBrandMark().padding(.bottom, 24)
                    BessieSectionLabel("Trouble")
                    troubleRailFact("Connection", diagnostic.apiHealthy ? "Connected" : "Unavailable")
                    troubleRailFact("Runtime", diagnostic.runtime?.source.rawValue.capitalized ?? "Unresolved")
                    troubleRailFact("Session", diagnostic.session)
                    Spacer()
                    Text("Herdr may still be running even when Bessie cannot connect.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(BessieDesign.subtle)
                }
                .padding(20)
                .frame(width: 210)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .bessieSurface(base: BessieDesign.rail)

                VStack(alignment: .leading, spacing: 16) {
                    Text("Trouble").font(.system(size: 28, weight: .medium))
                    Text(message).foregroundStyle(BessieDesign.text)
                    VStack(alignment: .leading, spacing: 10) {
                        fact("Runtime", diagnostic.runtime?.source.rawValue ?? "Unresolved")
                        fact("Path", diagnostic.runtime?.url.path ?? "Unavailable")
                        fact("Protocol", diagnostic.observedProtocol.map(String.init) ?? "Unknown")
                        fact("Session", diagnostic.session)
                        fact("API", diagnostic.apiHealthy ? "Healthy" : "Unavailable")
                        fact("Terminal controller", diagnostic.terminalControllerHealthy ? "Healthy" : "Unavailable")
                    }
                    .padding(14)
                    .bessieSurface(base: BessieDesign.panel)
                    Spacer()
                    HStack {
                        ForEach(diagnostic.availableActions, id: \.self) { action in
                            actionButton(action)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .bessieSurface(base: BessieDesign.background)
            }
            .padding(BessieDesign.cardGap)
        }
    }

    private var message: String {
        diagnostic.finding == .bundledIntegrity ? "This copy of Bessie is damaged. Reinstall Bessie from a trusted package." : "Bessie could not finish setup. The facts below can help identify the failure."
    }
    private func fact(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(BessieDesign.subtle); Spacer(); Text(value).font(.system(size: 11, design: .monospaced)).lineLimit(1) }
    }
    private func troubleRailFact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(BessieDesign.faint)
            Text(value).font(.system(size: 11, design: .monospaced)).lineLimit(1)
        }
        .padding(.top, 14)
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
            Button("Open settings") { openSettings() }.buttonStyle(BessieSecondaryButtonStyle())
        }
    }
}
