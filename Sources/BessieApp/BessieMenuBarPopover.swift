import BessieCore
import SwiftUI

struct BessieMenuBarPresentation: Equatable {
    struct Row: Identifiable, Equatable {
        let title: String
        let secondaryIdentity: String?
        let location: String
        let provider: String?
        let target: RoutedPaneTarget
        var id: String { "\(target.connectionID)::\(target.paneID)" }

        init(
            title: String,
            secondaryIdentity: String? = nil,
            location: String,
            provider: String?,
            target: RoutedPaneTarget
        ) {
            self.title = title
            self.secondaryIdentity = secondaryIdentity == title ? nil : secondaryIdentity
            self.location = location
            self.provider = provider
            self.target = target
        }

        var announcedTitle: String {
            [title, secondaryIdentity].compactMap { $0 }.joined(separator: ", ")
        }
    }

    let needsYou: [Row]
    let workingRows: [Row]
    let working: Int
    let done: Int
    let idle: Int
    let unknown: Int

    var needsYouCount: Int { needsYou.count }
    var showsUnknownSummary: Bool { unknown > 0 }

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
        done: 4,
        idle: 3,
        unknown: 1,
    )

    private init(needsYou: [Row], workingRows: [Row], working: Int, done: Int, idle: Int, unknown: Int) {
        self.needsYou = needsYou
        self.workingRows = workingRows
        self.working = working
        self.done = done
        self.idle = idle
        self.unknown = unknown
    }

    init(
        agents: [ConnectedAgentProjection],
        freshConnectionIDs: Set<String>,
        snoozedIncarnations: Set<BessiePaneIncarnation> = []
    ) {
        let fresh = agents.filter {
            freshConnectionIDs.contains($0.connectionID)
                && !snoozedIncarnations.contains(BessiePaneIncarnation(
                    connectionID: $0.connectionID,
                    paneID: $0.paneID,
                    terminalID: $0.agent.terminalID
                ))
        }
        let rows = fresh.map { item in
            (
                state: AgentSemanticState(herdrValue: item.agent.agentStatus),
                row: Row(
                    title: item.primaryTitle,
                    secondaryIdentity: item.secondaryIdentity,
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
        done = rows.count { $0.state == .done }
        idle = rows.count { $0.state == .idle }
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
            unknown > 0
                ? "Bessie, \(needsYouCount) agents need you, \(unknown) unknown"
                : "Bessie, \(needsYouCount) agents need you"
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
            freshConnectionIDs: fleet.connectedConnectionIDs,
            snoozedIncarnations: settings.snoozedPaneIncarnations()
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
                total("Done", presentation.done, state: .done)
                total("Idle", presentation.idle, state: .idle)
                if presentation.showsUnknownSummary {
                    total("Unknown", presentation.unknown, state: .unknown)
                }
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
                        Text([row.secondaryIdentity, row.location].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
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
        .accessibilityLabel("Open \(row.announcedTitle), \(label), \(row.location)")
    }

    private func total(_ label: String, _ count: Int, state: AgentSemanticState) -> some View {
        HStack(spacing: 8) {
            BessieStatusGlyph(state: state)
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
