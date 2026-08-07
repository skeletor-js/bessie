import BessieCore
import SwiftUI

struct BessieMenuBarPresentation: Equatable {
    struct Row: Identifiable, Equatable {
        let title: String
        let location: String
        let provider: String?
        let target: RoutedPaneTarget
        var id: String { "\(target.connectionID)::\(target.paneID)" }
    }

    let needsYou: [Row]
    let workingRows: [Row]
    let working: Int
    let settled: Int
    let unknown: Int

    var needsYouCount: Int { needsYou.count }

    static let captureFixture = BessieMenuBarPresentation(
        needsYou: [
            Row(
                title: "Migrate docs to schema 3",
                location: "herdr-docs / main / schema",
                provider: "codex",
                target: RoutedPaneTarget(connectionID: "capture", workspaceID: "docs", tabID: "main", paneID: "schema")
            ),
            Row(
                title: "Replace the cream theme",
                location: "bessie / dev / theme",
                provider: "claude",
                target: RoutedPaneTarget(connectionID: "capture", workspaceID: "bessie", tabID: "dev", paneID: "theme")
            ),
        ],
        workingRows: [
            Row(
                title: "Verify terminal input",
                location: "bessie / dev / terminal",
                provider: "amp",
                target: RoutedPaneTarget(connectionID: "capture", workspaceID: "bessie", tabID: "dev", paneID: "terminal")
            ),
            Row(
                title: "Run release checks",
                location: "bessie / dev / verify",
                provider: "codex",
                target: RoutedPaneTarget(connectionID: "capture", workspaceID: "bessie", tabID: "dev", paneID: "verify")
            ),
        ],
        working: 2,
        settled: 7,
        unknown: 1,
    )

    private init(needsYou: [Row], workingRows: [Row], working: Int, settled: Int, unknown: Int) {
        self.needsYou = needsYou
        self.workingRows = workingRows
        self.working = working
        self.settled = settled
        self.unknown = unknown
    }

    init(
        agents: [ConnectedAgentProjection],
        freshConnectionIDs: Set<String>
    ) {
        let fresh = agents.filter { freshConnectionIDs.contains($0.connectionID) }
        let rows = fresh.map { item in
            (
                state: AgentSemanticState(herdrValue: item.agent.agentStatus),
                row: Row(
                    title: item.agent.title ?? item.agent.identity,
                    location: [ConnectionDisplayLabel(connection: item.connection).short, item.workspaceLabel, item.tabLabel]
                        .compactMap { $0 }.joined(separator: " · "),
                    provider: item.agent.displayAgent ?? item.agent.agent,
                    target: RoutedPaneTarget(connectionID: item.connectionID, workspaceID: item.workspaceID,
                                             tabID: item.tabID, paneID: item.paneID)
                )
            )
        }
        needsYou = rows.filter { $0.state == .blocked }.map { $0.row }
            .sorted { $0.location.localizedCaseInsensitiveCompare($1.location) == .orderedAscending }
        workingRows = rows.filter { $0.state == .working }.map { $0.row }
            .sorted { $0.location.localizedCaseInsensitiveCompare($1.location) == .orderedAscending }
        working = workingRows.count
        settled = fresh.count {
            let state = AgentSemanticState(herdrValue: $0.agent.agentStatus)
            return state == .done || state == .idle
        }
        unknown = fresh.count { AgentSemanticState(herdrValue: $0.agent.agentStatus) == .unknown }
    }

    func badgeCount(policy: BessieMenuBarBadgePolicy) -> Int? {
        switch policy {
        case .needsYou: needsYouCount
        case .needsYouAndUnknown: needsYouCount + unknown
        case .nothing: nil
        }
    }

    func badgeAccessibilityLabel(policy: BessieMenuBarBadgePolicy) -> String {
        switch policy {
        case .needsYou:
            "Bessie, \(needsYouCount) agents need you"
        case .needsYouAndUnknown:
            "Bessie, \(needsYouCount) agents need you, \(unknown) unknown"
        case .nothing:
            "Bessie"
        }
    }
}

struct BessieMenuBarPopover: View {
    @ObservedObject var fleet: ConnectionFleetViewModel
    @ObservedObject var settings: BessieSettingsModel
    let openBessie: () -> Void
    let openRow: (RoutedPaneTarget) -> Void

    private var presentation: BessieMenuBarPresentation {
        if ProcessInfo.processInfo.environment["BESSIE_DESIGN_ARTBOARD"] == "15" {
            return .captureFixture
        }
        return BessieMenuBarPresentation(
            agents: fleet.agents,
            freshConnectionIDs: fleet.connectedConnectionIDs
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(presentation.needsYouCount) need you · \(presentation.working) working")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .overlay(alignment: .bottom) { Divider() }

            if !presentation.needsYou.isEmpty {
                VStack(spacing: 5) {
                    ForEach(presentation.needsYou) { row in
                        paneRow(row, state: .blocked, label: "Needs you", highlighted: true)
                    }
                }
                .padding(5)
            }

            if !presentation.workingRows.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("WORKING")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(BessieDesign.faint)
                        .padding(.horizontal, 9)
                        .padding(.top, 4)
                    ForEach(presentation.workingRows) { row in
                        paneRow(row, state: .working, label: "Working", highlighted: false)
                    }
                }
                .padding(5)
                .overlay(alignment: .top) { Divider() }
            }

            VStack(spacing: 0) {
                total("Settled", presentation.settled, color: BessieDesign.done, symbol: .ring)
                total("Unknown", presentation.unknown, color: BessieDesign.idle, symbol: .diamond)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .overlay(alignment: .top) { Divider() }

            HStack {
                Button(action: openBessie) {
                    HStack {
                        Text("Open Bessie")
                        Spacer()
                        Text("⌘⇧B").font(.system(size: 10, design: .monospaced)).foregroundStyle(BessieDesign.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Bessie")
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(BessieDesign.inset)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 312)
        .background(BessieDesign.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(BessieDesign.borderStrong, lineWidth: 1)
        }
        .preferredColorScheme(settings.preferences.appearance.preferredColorScheme)
        .background(BessieWindowSnapshotProbe(role: "menu-bar"))
    }

    private enum SummarySymbol { case ring, diamond }

    private func paneRow(
        _ row: BessieMenuBarPresentation.Row,
        state: AgentSemanticState,
        label: String,
        highlighted: Bool
    ) -> some View {
        Button { openRow(row.target) } label: {
            HStack(spacing: 8) {
                BessieStatusGlyph(state: state)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(BessieDesign.strong)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(row.location).lineLimit(1)
                        Spacer(minLength: 2)
                        if let provider = row.provider {
                            BessieProviderMark(provider: provider)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BessieDesign.faint)
                }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(highlighted ? BessieDesign.selected : BessieDesign.inset,
                        in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(row.title), \(label), \(row.location)")
    }

    private func total(_ label: String, _ count: Int, color: BessieSemanticColor, symbol: SummarySymbol) -> some View {
        HStack(spacing: 8) {
            BessieStatusGlyph(state: symbol == .diamond ? .unknown : (label == "Working" ? .working : .done))
            Text(label).foregroundStyle(BessieDesign.subtle)
            Spacer()
            Text("\(count)").monospacedDigit().foregroundStyle(BessieDesign.faint)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 9)
        .frame(height: 31)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label), \(count)")
    }
}
